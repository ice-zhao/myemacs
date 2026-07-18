# bash/zsh completion support for core Git.
#
# Copyright (C) 2006,2007 Shawn O. Pearce <spearce@spearce.org>
# Conceptually based on gcompletion (http://gweb.hawaga.org.uk/).
# Distributed under the GNU General Public License, version 2.0.
#
# The contained completion routines provide support for completing:
#
#    *) local and remote branch names
#    *) local and remote tag names
#    *) .g/remotes file names
#    *) g 'subcommands'
#    *) g email aliases for g-send-email
#    *) tree paths within 'ref:path/to/file' expressions
#    *) file paths within current working directory and index
#    *) common --long-options
#
# To use these routines:
#
#    1) Copy this file to somewhere (e.g. ~/.g-completion.bash).
#    2) Add the following line to your .bashrc/.zshrc:
#        source ~/.g-completion.bash
#    3) Consider changing your PS1 to also show the current branch,
#       see g-prompt.sh for details.
#
# If you use complex aliases of form '!f() { ... }; f', you can use the null
# command ':' as the first command in the function body to declare the desired
# completion style.  For example '!f() { : g commit ; ... }; f' will
# tell the completion to use commit completion.  This also works with aliases
# of form "!sh -c '...'".  For example, "!sh -c ': g commit ; ... '".
# Note that "g" is optional --- '!f() { : commit; ...}; f' would complete
# just like the 'g commit' command.
#
# To add completion for g subcommands that are implemented in external
# scripts, define a function of the form '_g_${subcommand}' while replacing
# all dashes with underscores, and the main g completion will make use of it.
# For example, to add completion for 'g do-stuff' (which could e.g. live
# in /usr/bin/g-do-stuff), name the completion function '_g_do_stuff'.
# See _g_show, _g_bisect etc. below for more examples.
#
# If you have a shell command that is not part of g (and is not called as a
# g subcommand), but you would still like g-style completion for it, use
# __g_complete. For example, to use the same completion as for 'g log' also
# for the 'gl' command:
#
#   __g_complete gl g_log
#
# Or if the 'gk' command should be completed the same as 'gk':
#
#   __g_complete gk gk
#
# The second parameter of __g_complete gives the completion function; it is
# resolved as a function named "$2", or "__$2_main", or "_$2" in that order.
# In the examples above, the actual functions used for completion will be
# _g_log and __gk_main.
#
# Compatible with bash 3.2.57.
#
# You can set the following environment variables to influence the behavior of
# the completion routines:
#
#   GIT_COMPLETION_CHECKOUT_NO_GUESS
#
#     When set to "1", do not include "DWIM" suggestions in g-checkout
#     and g-switch completion (e.g., completing "foo" when "origin/foo"
#     exists).
#
#   GIT_COMPLETION_SHOW_ALL_COMMANDS
#
#     When set to "1" suggest all commands, including plumbing commands
#     which are hidden by default (e.g. "cat-file" on "g ca<TAB>").
#
#   GIT_COMPLETION_SHOW_ALL
#
#     When set to "1" suggest all options, including options which are
#     typically hidden (e.g. '--allow-empty' for 'g commit').
#
#   GIT_COMPLETION_IGNORE_CASE
#
#     When set, uses for-each-ref '--ignore-case' to find refs that match
#     case insensitively, even on systems with case sensitive file systems
#     (e.g., completing tag name "FOO" on "g checkout f<TAB>").

case "$COMP_WORDBREAKS" in
*:*) : great ;;
*)   COMP_WORDBREAKS="$COMP_WORDBREAKS:"
esac

# Discovers the path to the g repository taking any '--g-dir=<path>' and
# '-C <path>' options into account and stores it in the $__g_repo_path
# variable.
__g_find_repo_path ()
{
	if [ -n "${__g_repo_path-}" ]; then
		# we already know where it is
		return
	fi

	if [ -n "${__g_C_args-}" ]; then
		__g_repo_path="$(g "${__g_C_args[@]}" \
			${__g_dir:+--g-dir="$__g_dir"} \
			rev-parse --absolute-g-dir 2>/dev/null)"
	elif [ -n "${__g_dir-}" ]; then
		test -d "$__g_dir" &&
		__g_repo_path="$__g_dir"
	elif [ -n "${GIT_DIR-}" ]; then
		test -d "$GIT_DIR" &&
		__g_repo_path="$GIT_DIR"
	elif [ -d .g ]; then
		__g_repo_path=.g
	else
		__g_repo_path="$(g rev-parse --g-dir 2>/dev/null)"
	fi
}

# Deprecated: use __g_find_repo_path() and $__g_repo_path instead
# __gdir accepts 0 or 1 arguments (i.e., location)
# returns location of .g repo
__gdir ()
{
	if [ -z "${1-}" ]; then
		__g_find_repo_path || return 1
		echo "$__g_repo_path"
	elif [ -d "$1/.g" ]; then
		echo "$1/.g"
	else
		echo "$1"
	fi
}

# Runs g with all the options given as argument, respecting any
# '--g-dir=<path>' and '-C <path>' options present on the command line
__g ()
{
	g ${__g_C_args:+"${__g_C_args[@]}"} \
		${__g_dir:+--g-dir="$__g_dir"} "$@" 2>/dev/null
}

# Helper function to read the first line of a file into a variable.
# __g_eread requires 2 arguments, the file path and the name of the
# variable, in that order.
#
# This is taken from g-prompt.sh.
__g_eread ()
{
	test -r "$1" && IFS=$'\r\n' read -r "$2" <"$1"
}

# Runs g in $__g_repo_path to determine whether a pseudoref exists.
# 1: The pseudo-ref to search
__g_pseudoref_exists ()
{
	local ref=$1
	local head

	__g_find_repo_path

	# If the reftable is in use, we have to shell out to 'g rev-parse'
	# to determine whether the ref exists instead of looking directly in
	# the filesystem to determine whether the ref exists. Otherwise, use
	# Bash builtins since executing Git commands are expensive on some
	# platforms.
	if __g_eread "$__g_repo_path/HEAD" head; then
		if [ "$head" == "ref: refs/heads/.invalid" ]; then
			__g show-ref --exists "$ref"
			return $?
		fi
	fi

	[ -f "$__g_repo_path/$ref" ]
}

# Removes backslash escaping, single quotes and double quotes from a word,
# stores the result in the variable $dequoted_word.
# 1: The word to dequote.
__g_dequote ()
{
	local rest="$1" len ch

	dequoted_word=""

	while test -n "$rest"; do
		len=${#dequoted_word}
		dequoted_word="$dequoted_word${rest%%[\\\'\"]*}"
		rest="${rest:$((${#dequoted_word}-$len))}"

		case "${rest:0:1}" in
		\\)
			ch="${rest:1:1}"
			case "$ch" in
			$'\n')
				;;
			*)
				dequoted_word="$dequoted_word$ch"
				;;
			esac
			rest="${rest:2}"
			;;
		\')
			rest="${rest:1}"
			len=${#dequoted_word}
			dequoted_word="$dequoted_word${rest%%\'*}"
			rest="${rest:$((${#dequoted_word}-$len+1))}"
			;;
		\")
			rest="${rest:1}"
			while test -n "$rest" ; do
				len=${#dequoted_word}
				dequoted_word="$dequoted_word${rest%%[\\\"]*}"
				rest="${rest:$((${#dequoted_word}-$len))}"
				case "${rest:0:1}" in
				\\)
					ch="${rest:1:1}"
					case "$ch" in
					\"|\\|\$|\`)
						dequoted_word="$dequoted_word$ch"
						;;
					$'\n')
						;;
					*)
						dequoted_word="$dequoted_word\\$ch"
						;;
					esac
					rest="${rest:2}"
					;;
				\")
					rest="${rest:1}"
					break
					;;
				esac
			done
			;;
		esac
	done
}

# The following function is based on code from:
#
#   bash_completion - programmable completion functions for bash 3.2+
#
#   Copyright © 2006-2008, Ian Macdonald <ian@caliban.org>
#             © 2009-2010, Bash Completion Maintainers
#                     <bash-completion-devel@lists.alioth.debian.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2, or (at your option)
#   any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, see <http://www.gnu.org/licenses/>.
#
#   The latest version of this software can be obtained here:
#
#   http://bash-completion.alioth.debian.org/
#
#   RELEASE: 2.x

# This function can be used to access a tokenized list of words
# on the command line:
#
#	__g_reassemble_comp_words_by_ref '=:'
#	if test "${words_[cword_-1]}" = -w
#	then
#		...
#	fi
#
# The argument should be a collection of characters from the list of
# word completion separators (COMP_WORDBREAKS) to treat as ordinary
# characters.
#
# This is roughly equivalent to going back in time and setting
# COMP_WORDBREAKS to exclude those characters.  The intent is to
# make option types like --date=<type> and <rev>:<path> easy to
# recognize by treating each shell word as a single token.
#
# It is best not to set COMP_WORDBREAKS directly because the value is
# shared with other completion scripts.  By the time the completion
# function gets called, COMP_WORDS has already been populated so local
# changes to COMP_WORDBREAKS have no effect.
#
# Output: words_, cword_, cur_.

__g_reassemble_comp_words_by_ref()
{
	local exclude i j first
	# Which word separators to exclude?
	exclude="${1//[^$COMP_WORDBREAKS]}"
	cword_=$COMP_CWORD
	if [ -z "$exclude" ]; then
		words_=("${COMP_WORDS[@]}")
		return
	fi
	# List of word completion separators has shrunk;
	# re-assemble words to complete.
	for ((i=0, j=0; i < ${#COMP_WORDS[@]}; i++, j++)); do
		# Append each nonempty word consisting of just
		# word separator characters to the current word.
		first=t
		while
			[ $i -gt 0 ] &&
			[ -n "${COMP_WORDS[$i]}" ] &&
			# word consists of excluded word separators
			[ "${COMP_WORDS[$i]//[^$exclude]}" = "${COMP_WORDS[$i]}" ]
		do
			# Attach to the previous token,
			# unless the previous token is the command name.
			if [ $j -ge 2 ] && [ -n "$first" ]; then
				((j--))
			fi
			first=
			words_[$j]=${words_[j]}${COMP_WORDS[i]}
			if [ $i = $COMP_CWORD ]; then
				cword_=$j
			fi
			if (($i < ${#COMP_WORDS[@]} - 1)); then
				((i++))
			else
				# Done.
				return
			fi
		done
		words_[$j]=${words_[j]}${COMP_WORDS[i]}
		if [ $i = $COMP_CWORD ]; then
			cword_=$j
		fi
	done
}

if ! type _get_comp_words_by_ref >/dev/null 2>&1; then
_get_comp_words_by_ref ()
{
	local exclude cur_ words_ cword_
	if [ "$1" = "-n" ]; then
		exclude=$2
		shift 2
	fi
	__g_reassemble_comp_words_by_ref "$exclude"
	cur_=${words_[cword_]}
	while [ $# -gt 0 ]; do
		case "$1" in
		cur)
			cur=$cur_
			;;
		prev)
			prev=${words_[$cword_-1]}
			;;
		words)
			words=("${words_[@]}")
			;;
		cword)
			cword=$cword_
			;;
		esac
		shift
	done
}
fi

# Fills the COMPREPLY array with prefiltered words without any additional
# processing.
# Callers must take care of providing only words that match the current word
# to be completed and adding any prefix and/or suffix (trailing space!), if
# necessary.
# 1: List of newline-separated matching completion words, complete with
#    prefix and suffix.
__gcomp_direct ()
{
	local IFS=$'\n'

	COMPREPLY=($1)
}

# Similar to __gcomp_direct, but appends to COMPREPLY instead.
# Callers must take care of providing only words that match the current word
# to be completed and adding any prefix and/or suffix (trailing space!), if
# necessary.
# 1: List of newline-separated matching completion words, complete with
#    prefix and suffix.
__gcomp_direct_append ()
{
	local IFS=$'\n'

	COMPREPLY+=($1)
}

__gcompappend ()
{
	local x i=${#COMPREPLY[@]}
	for x in $1; do
		if [[ "$x" == "$3"* ]]; then
			COMPREPLY[i++]="$2$x$4"
		fi
	done
}

__gcompadd ()
{
	COMPREPLY=()
	__gcompappend "$@"
}

# Generates completion reply, appending a space to possible completion words,
# if necessary.
# It accepts 1 to 4 arguments:
# 1: List of possible completion words.
# 2: A prefix to be added to each possible completion word (optional).
# 3: Generate possible completion matches for this word (optional).
# 4: A suffix to be appended to each possible completion word (optional).
__gcomp ()
{
	local cur_="${3-$cur}"

	case "$cur_" in
	*=)
		;;
	--no-*)
		local c i=0 IFS=$' \t\n'
		for c in $1; do
			if [[ $c == "--" ]]; then
				continue
			fi
			c="$c${4-}"
			if [[ $c == "$cur_"* ]]; then
				case $c in
				--*=|*.) ;;
				*) c="$c " ;;
				esac
				COMPREPLY[i++]="${2-}$c"
			fi
		done
		;;
	*)
		local c i=0 IFS=$' \t\n'
		for c in $1; do
			if [[ $c == "--" ]]; then
				c="--no-...${4-}"
				if [[ $c == "$cur_"* ]]; then
					COMPREPLY[i++]="${2-}$c "
				fi
				break
			fi
			c="$c${4-}"
			if [[ $c == "$cur_"* ]]; then
				case $c in
				*=|*.) ;;
				*) c="$c " ;;
				esac
				COMPREPLY[i++]="${2-}$c"
			fi
		done
		;;
	esac
}

# Clear the variables caching builtins' options when (re-)sourcing
# the completion script.
if [[ -n ${ZSH_VERSION-} ]]; then
	unset ${(M)${(k)parameters[@]}:#__gcomp_builtin_*} 2>/dev/null
else
	unset $(compgen -v __gcomp_builtin_)
fi

# This function is equivalent to
#
#    ___g_resolved_builtins=$(g xxx --g-completion-helper)
#
# except that the result of the execution is cached.
#
# Accept 1-3 arguments:
# 1: the g command to execute, this is also the cache key
#    (use "_" when the command contains spaces, e.g. "remote add"
#    becomes "remote_add")
# 2: extra options to be added on top (e.g. negative forms)
# 3: options to be excluded
__g_resolve_builtins ()
{
	local cmd="$1"
	local incl="${2-}"
	local excl="${3-}"

	local var=__gcomp_builtin_"${cmd//-/_}"
	local options
	eval "options=\${$var-}"

	if [ -z "$options" ]; then
		local completion_helper
		if [ "${GIT_COMPLETION_SHOW_ALL-}" = "1" ]; then
			completion_helper="--g-completion-helper-all"
		else
			completion_helper="--g-completion-helper"
		fi
		# leading and trailing spaces are significant to make
		# option removal work correctly.
		options=" $incl $(__g ${cmd/_/ } $completion_helper) " || return

		for i in $excl; do
			options="${options/ $i / }"
		done
		eval "$var=\"$options\""
	fi

	___g_resolved_builtins="$options"
}

# This function is equivalent to
#
#    __gcomp "$(g xxx --g-completion-helper) ..."
#
# except that the output is cached. Accept 1-3 arguments:
# 1: the g command to execute, this is also the cache key
#    (use "_" when the command contains spaces, e.g. "remote add"
#    becomes "remote_add")
# 2: extra options to be added on top (e.g. negative forms)
# 3: options to be excluded
__gcomp_builtin ()
{
	__g_resolve_builtins "$1" "$2" "$3"

	__gcomp "$___g_resolved_builtins"
}

# Variation of __gcomp_nl () that appends to the existing list of
# completion candidates, COMPREPLY.
__gcomp_nl_append ()
{
	local IFS=$'\n'
	__gcompappend "$1" "${2-}" "${3-$cur}" "${4- }"
}

# Generates completion reply from newline-separated possible completion words
# by appending a space to all of them.
# It accepts 1 to 4 arguments:
# 1: List of possible completion words, separated by a single newline.
# 2: A prefix to be added to each possible completion word (optional).
# 3: Generate possible completion matches for this word (optional).
# 4: A suffix to be appended to each possible completion word instead of
#    the default space (optional).  If specified but empty, nothing is
#    appended.
__gcomp_nl ()
{
	COMPREPLY=()
	__gcomp_nl_append "$@"
}

# Fills the COMPREPLY array with prefiltered paths without any additional
# processing.
# Callers must take care of providing only paths that match the current path
# to be completed and adding any prefix path components, if necessary.
# 1: List of newline-separated matching paths, complete with all prefix
#    path components.
__gcomp_file_direct ()
{
	local IFS=$'\n'

	COMPREPLY=($1)

	# use a hack to enable file mode in bash < 4
	compopt -o filenames +o nospace 2>/dev/null ||
	compgen -f /non-existing-dir/ >/dev/null ||
	true
}

# Generates completion reply with compgen from newline-separated possible
# completion filenames.
# It accepts 1 to 3 arguments:
# 1: List of possible completion filenames, separated by a single newline.
# 2: A directory prefix to be added to each possible completion filename
#    (optional).
# 3: Generate possible completion matches for this word (optional).
__gcomp_file ()
{
	local IFS=$'\n'

	# XXX does not work when the directory prefix contains a tilde,
	# since tilde expansion is not applied.
	# This means that COMPREPLY will be empty and Bash default
	# completion will be used.
	__gcompadd "$1" "${2-}" "${3-$cur}" ""

	# use a hack to enable file mode in bash < 4
	compopt -o filenames +o nospace 2>/dev/null ||
	compgen -f /non-existing-dir/ >/dev/null ||
	true
}

# Find the current subcommand for commands that follow the syntax:
#
#    g <command> <subcommand>
#
# 1: List of possible subcommands.
# 2: Optional subcommand to return when none is found.
__g_find_subcommand ()
{
	local subcommand subcommands="$1" default_subcommand="$2"

	for subcommand in $subcommands; do
		if [ "$subcommand" = "${words[__g_cmd_idx+1]}" ]; then
			echo $subcommand
			return
		fi
	done

	echo $default_subcommand
}

# Execute 'g ls-files', unless the --committable option is specified, in
# which case it runs 'g diff-index' to find out the files that can be
# committed.  It return paths relative to the directory specified in the first
# argument, and using the options specified in the second argument.
__g_ls_files_helper ()
{
	if [ "$2" = "--committable" ]; then
		__g -C "$1" -c core.quotePath=false diff-index \
			--name-only --relative HEAD -- "${3//\\/\\\\}*"
	else
		# NOTE: $2 is not quoted in order to support multiple options
		__g -C "$1" -c core.quotePath=false ls-files \
			--exclude-standard $2 -- "${3//\\/\\\\}*"
	fi
}


# __g_index_files accepts 1 or 2 arguments:
# 1: Options to pass to ls-files (required).
# 2: A directory path (optional).
#    If provided, only files within the specified directory are listed.
#    Sub directories are never recursed.  Path must have a trailing
#    slash.
# 3: List only paths matching this path component (optional).
__g_index_files ()
{
	local root="$2" match="$3"

	__g_ls_files_helper "$root" "$1" "${match:-?}" |
	awk -F / -v pfx="${2//\\/\\\\}" '{
		paths[$1] = 1
	}
	END {
		for (p in paths) {
			if (substr(p, 1, 1) != "\"") {
				# No special characters, easy!
				print pfx p
				continue
			}

			# The path is quoted.
			p = dequote(p)
			if (p == "")
				continue

			# Even when a directory name itself does not contain
			# any special characters, it will still be quoted if
			# any of its (stripped) trailing path components do.
			# Because of this we may have seen the same directory
			# both quoted and unquoted.
			if (p in paths)
				# We have seen the same directory unquoted,
				# skip it.
				continue
			else
				print pfx p
		}
	}
	function dequote(p,    bs_idx, out, esc, esc_idx, dec) {
		# Skip opening double quote.
		p = substr(p, 2)

		# Interpret backslash escape sequences.
		while ((bs_idx = index(p, "\\")) != 0) {
			out = out substr(p, 1, bs_idx - 1)
			esc = substr(p, bs_idx + 1, 1)
			p = substr(p, bs_idx + 2)

			if ((esc_idx = index("abtvfr\"\\", esc)) != 0) {
				# C-style one-character escape sequence.
				out = out substr("\a\b\t\v\f\r\"\\",
						 esc_idx, 1)
			} else if (esc == "n") {
				# Uh-oh, a newline character.
				# We cannot reliably put a pathname
				# containing a newline into COMPREPLY,
				# and the newline would create a mess.
				# Skip this path.
				return ""
			} else {
				# Must be a \nnn octal value, then.
				dec = esc             * 64 + \
				      substr(p, 1, 1) * 8  + \
				      substr(p, 2, 1)
				out = out sprintf("%c", dec)
				p = substr(p, 3)
			}
		}
		# Drop closing double quote, if there is one.
		# (There is not any if this is a directory, as it was
		# already stripped with the trailing path components.)
		if (substr(p, length(p), 1) == "\"")
			out = out substr(p, 1, length(p) - 1)
		else
			out = out p

		return out
	}'
}

# __g_complete_index_file requires 1 argument:
# 1: the options to pass to ls-file
#
# The exception is --committable, which finds the files appropriate commit.
__g_complete_index_file ()
{
	local dequoted_word pfx="" cur_

	__g_dequote "$cur"

	case "$dequoted_word" in
	?*/*)
		pfx="${dequoted_word%/*}/"
		cur_="${dequoted_word##*/}"
		;;
	*)
		cur_="$dequoted_word"
	esac

	__gcomp_file_direct "$(__g_index_files "$1" "$pfx" "$cur_")"
}

# Lists branches from the local repository.
# 1: A prefix to be added to each listed branch (optional).
# 2: List only branches matching this word (optional; list all branches if
#    unset or empty).
# 3: A suffix to be appended to each listed branch (optional).
__g_heads ()
{
	local pfx="${1-}" cur_="${2-}" sfx="${3-}"

	__g for-each-ref --format="${pfx//\%/%%}%(refname:strip=2)$sfx" \
			${GIT_COMPLETION_IGNORE_CASE+--ignore-case} \
			"refs/heads/$cur_*" "refs/heads/$cur_*/**"
}

# Lists branches from remote repositories.
# 1: A prefix to be added to each listed branch (optional).
# 2: List only branches matching this word (optional; list all branches if
#    unset or empty).
# 3: A suffix to be appended to each listed branch (optional).
__g_remote_heads ()
{
	local pfx="${1-}" cur_="${2-}" sfx="${3-}"

	__g for-each-ref --format="${pfx//\%/%%}%(refname:strip=2)$sfx" \
			${GIT_COMPLETION_IGNORE_CASE+--ignore-case} \
			"refs/remotes/$cur_*" "refs/remotes/$cur_*/**"
}

# Lists tags from the local repository.
# Accepts the same positional parameters as __g_heads() above.
__g_tags ()
{
	local pfx="${1-}" cur_="${2-}" sfx="${3-}"

	__g for-each-ref --format="${pfx//\%/%%}%(refname:strip=2)$sfx" \
			${GIT_COMPLETION_IGNORE_CASE+--ignore-case} \
			"refs/tags/$cur_*" "refs/tags/$cur_*/**"
}

# List unique branches from refs/remotes used for 'g checkout' and 'g
# switch' tracking DWIMery.
# 1: A prefix to be added to each listed branch (optional)
# 2: List only branches matching this word (optional; list all branches if
#    unset or empty).
# 3: A suffix to be appended to each listed branch (optional).
__g_dwim_remote_heads ()
{
	local pfx="${1-}" cur_="${2-}" sfx="${3-}"
	local fer_pfx="${pfx//\%/%%}" # "escape" for-each-ref format specifiers

	# employ the heuristic used by g checkout and g switch
	# Try to find a remote branch that cur_es the completion word
	# but only output if the branch name is unique
	__g for-each-ref --format="$fer_pfx%(refname:strip=3)$sfx" \
		--sort="refname:strip=3" \
		${GIT_COMPLETION_IGNORE_CASE+--ignore-case} \
		"refs/remotes/*/$cur_*" "refs/remotes/*/$cur_*/**" | \
	uniq -u
}

# Lists refs from the local (by default) or from a remote repository.
# It accepts 0, 1 or 2 arguments:
# 1: The remote to list refs from (optional; ignored, if set but empty).
#    Can be the name of a configured remote, a path, or a URL.
# 2: In addition to local refs, list unique branches from refs/remotes/ for
#    'g checkout's tracking DWIMery (optional; ignored, if set but empty).
# 3: A prefix to be added to each listed ref (optional).
# 4: List only refs matching this word (optional; list all refs if unset or
#    empty).
# 5: A suffix to be appended to each listed ref (optional; ignored, if set
#    but empty).
#
# Use __g_complete_refs() instead.
__g_refs ()
{
	local i hash dir track="${2-}"
	local list_refs_from=path remote="${1-}"
	local format refs
	local pfx="${3-}" cur_="${4-$cur}" sfx="${5-}"
	local match="${4-}"
	local umatch="${4-}"
	local fer_pfx="${pfx//\%/%%}" # "escape" for-each-ref format specifiers

	__g_find_repo_path
	dir="$__g_repo_path"

	if [ -z "$remote" ]; then
		if [ -z "$dir" ]; then
			return
		fi
	else
		if __g_is_configured_remote "$remote"; then
			# configured remote takes precedence over a
			# local directory with the same name
			list_refs_from=remote
		elif [ -d "$remote/.g" ]; then
			dir="$remote/.g"
		elif [ -d "$remote" ]; then
			dir="$remote"
		else
			list_refs_from=url
		fi
	fi

	if test "${GIT_COMPLETION_IGNORE_CASE:+1}" = "1"
	then
		# uppercase with tr instead of ${match,^^} for bash 3.2 compatibility
		umatch=$(echo "$match" | tr a-z A-Z 2>/dev/null || echo "$match")
	fi

	if [ "$list_refs_from" = path ]; then
		if [[ "$cur_" == ^* ]]; then
			pfx="$pfx^"
			fer_pfx="$fer_pfx^"
			cur_=${cur_#^}
			match=${match#^}
			umatch=${umatch#^}
		fi
		case "$cur_" in
		refs|refs/*)
			format="refname"
			refs=("$match*" "$match*/**")
			track=""
			;;
		*)
			for i in HEAD FETCH_HEAD ORIG_HEAD MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_HEAD AUTO_MERGE; do
				case "$i" in
				$match*|$umatch*)
					if [ -e "$dir/$i" ]; then
						echo "$pfx$i$sfx"
					fi
					;;
				esac
			done
			format="refname:strip=2"
			refs=("refs/tags/$match*" "refs/tags/$match*/**"
				"refs/heads/$match*" "refs/heads/$match*/**"
				"refs/remotes/$match*" "refs/remotes/$match*/**")
			;;
		esac
		__g_dir="$dir" __g for-each-ref --format="$fer_pfx%($format)$sfx" \
			${GIT_COMPLETION_IGNORE_CASE+--ignore-case} \
			"${refs[@]}"
		if [ -n "$track" ]; then
			__g_dwim_remote_heads "$pfx" "$match" "$sfx"
		fi
		return
	fi
	case "$cur_" in
	refs|refs/*)
		__g ls-remote "$remote" "$match*" | \
		while read -r hash i; do
			case "$i" in
			*^{}) ;;
			*) echo "$pfx$i$sfx" ;;
			esac
		done
		;;
	*)
		if [ "$list_refs_from" = remote ]; then
			case "HEAD" in
			$match*|$umatch*)	echo "${pfx}HEAD$sfx" ;;
			esac
			__g for-each-ref --format="$fer_pfx%(refname:strip=3)$sfx" \
				${GIT_COMPLETION_IGNORE_CASE+--ignore-case} \
				"refs/remotes/$remote/$match*" \
				"refs/remotes/$remote/$match*/**"
		else
			local query_symref
			case "HEAD" in
			$match*|$umatch*)	query_symref="HEAD" ;;
			esac
			__g ls-remote "$remote" $query_symref \
				"refs/tags/$match*" "refs/heads/$match*" \
				"refs/remotes/$match*" |
			while read -r hash i; do
				case "$i" in
				*^{})	;;
				refs/*)	echo "$pfx${i#refs/*/}$sfx" ;;
				*)	echo "$pfx$i$sfx" ;;  # symbolic refs
				esac
			done
		fi
		;;
	esac
}

# Completes refs, short and long, local and remote, symbolic and pseudo.
#
# Usage: __g_complete_refs [<option>]...
# --remote=<remote>: The remote to list refs from, can be the name of a
#                    configured remote, a path, or a URL.
# --dwim: List unique remote branches for 'g switch's tracking DWIMery.
# --pfx=<prefix>: A prefix to be added to each ref.
# --cur=<word>: The current ref to be completed.  Defaults to the current
#               word to be completed.
# --sfx=<suffix>: A suffix to be appended to each ref instead of the default
#                 space.
# --mode=<mode>: What set of refs to complete, one of 'refs' (the default) to
#                complete all refs, 'heads' to complete only branches, or
#                'remote-heads' to complete only remote branches. Note that
#                --remote is only compatible with --mode=refs.
__g_complete_refs ()
{
	local remote= dwim= pfx= cur_="$cur" sfx=" " mode="refs"

	while test $# != 0; do
		case "$1" in
		--remote=*)	remote="${1##--remote=}" ;;
		--dwim)		dwim="yes" ;;
		# --track is an old spelling of --dwim
		--track)	dwim="yes" ;;
		--pfx=*)	pfx="${1##--pfx=}" ;;
		--cur=*)	cur_="${1##--cur=}" ;;
		--sfx=*)	sfx="${1##--sfx=}" ;;
		--mode=*)	mode="${1##--mode=}" ;;
		*)		return 1 ;;
		esac
		shift
	done

	# complete references based on the specified mode
	case "$mode" in
		refs)
			__gcomp_direct "$(__g_refs "$remote" "" "$pfx" "$cur_" "$sfx")" ;;
		heads)
			__gcomp_direct "$(__g_heads "$pfx" "$cur_" "$sfx")" ;;
		remote-heads)
			__gcomp_direct "$(__g_remote_heads "$pfx" "$cur_" "$sfx")" ;;
		*)
			return 1 ;;
	esac

	# Append DWIM remote branch names if requested
	if [ "$dwim" = "yes" ]; then
		__gcomp_direct_append "$(__g_dwim_remote_heads "$pfx" "$cur_" "$sfx")"
	fi
}

# __g_refs2 requires 1 argument (to pass to __g_refs)
# Deprecated: use __g_complete_fetch_refspecs() instead.
__g_refs2 ()
{
	local i
	for i in $(__g_refs "$1"); do
		echo "$i:$i"
	done
}

# Completes refspecs for fetching from a remote repository.
# 1: The remote repository.
# 2: A prefix to be added to each listed refspec (optional).
# 3: The ref to be completed as a refspec instead of the current word to be
#    completed (optional)
# 4: A suffix to be appended to each listed refspec instead of the default
#    space (optional).
__g_complete_fetch_refspecs ()
{
	local i remote="$1" pfx="${2-}" cur_="${3-$cur}" sfx="${4- }"

	__gcomp_direct "$(
		for i in $(__g_refs "$remote" "" "" "$cur_") ; do
			echo "$pfx$i:$i$sfx"
		done
		)"
}

# __g_refs_remotes requires 1 argument (to pass to ls-remote)
__g_refs_remotes ()
{
	local i hash
	__g ls-remote "$1" 'refs/heads/*' | \
	while read -r hash i; do
		echo "$i:refs/remotes/$1/${i#refs/heads/}"
	done
}

__g_remotes ()
{
	__g_find_repo_path
	test -d "$__g_repo_path/remotes" && ls -1 "$__g_repo_path/remotes"
	__g remote
}

# Returns true if $1 matches the name of a configured remote, false otherwise.
__g_is_configured_remote ()
{
	local remote
	for remote in $(__g_remotes); do
		if [ "$remote" = "$1" ]; then
			return 0
		fi
	done
	return 1
}

__g_list_merge_strategies ()
{
	LANG=C LC_ALL=C g merge -s help 2>&1 |
	sed -n -e '/[Aa]vailable strategies are: /,/^$/{
		s/\.$//
		s/.*://
		s/^[ 	]*//
		s/[ 	]*$//
		p
	}'
}

__g_merge_strategies=
# 'g merge -s help' (and thus detection of the merge strategy
# list) fails, unfortunately, if run outside of any g working
# tree.  __g_merge_strategies is set to the empty string in
# that case, and the detection will be repeated the next time it
# is needed.
__g_compute_merge_strategies ()
{
	test -n "$__g_merge_strategies" ||
	__g_merge_strategies=$(__g_list_merge_strategies)
}

__g_merge_strategy_options="ours theirs subtree subtree= patience
	histogram diff-algorithm= ignore-space-change ignore-all-space
	ignore-space-at-eol renormalize no-renormalize no-renames
	find-renames find-renames= rename-threshold="

__g_complete_revlist_file ()
{
	local dequoted_word pfx ls ref cur_="$cur"
	case "$cur_" in
	*..?*:*)
		return
		;;
	?*:*)
		ref="${cur_%%:*}"
		cur_="${cur_#*:}"

		__g_dequote "$cur_"

		case "$dequoted_word" in
		?*/*)
			pfx="${dequoted_word%/*}"
			cur_="${dequoted_word##*/}"
			ls="$ref:$pfx"
			pfx="$pfx/"
			;;
		*)
			cur_="$dequoted_word"
			ls="$ref"
			;;
		esac

		case "$COMP_WORDBREAKS" in
		*:*) : great ;;
		*)   pfx="$ref:$pfx" ;;
		esac

		__gcomp_file "$(__g ls-tree "$ls" \
				| sed 's/^.*	//
				       s/$//')" \
			"$pfx" "$cur_"
		;;
	*...*)
		pfx="${cur_%...*}..."
		cur_="${cur_#*...}"
		__g_complete_refs --pfx="$pfx" --cur="$cur_"
		;;
	*..*)
		pfx="${cur_%..*}.."
		cur_="${cur_#*..}"
		__g_complete_refs --pfx="$pfx" --cur="$cur_"
		;;
	*)
		__g_complete_refs
		;;
	esac
}

__g_complete_file ()
{
	__g_complete_revlist_file
}

__g_complete_revlist ()
{
	__g_complete_revlist_file
}

__g_complete_remote_or_refspec ()
{
	local cur_="$cur" cmd="${words[__g_cmd_idx]}"
	local i c=$((__g_cmd_idx+1)) remote="" pfx="" lhs=1 no_complete_refspec=0
	if [ "$cmd" = "remote" ]; then
		((c++))
	fi
	while [ $c -lt $cword ]; do
		i="${words[c]}"
		case "$i" in
		--mirror) [ "$cmd" = "push" ] && no_complete_refspec=1 ;;
		-d|--delete) [ "$cmd" = "push" ] && lhs=0 ;;
		--all)
			case "$cmd" in
			push) no_complete_refspec=1 ;;
			fetch)
				return
				;;
			*) ;;
			esac
			;;
		--multiple) no_complete_refspec=1; break ;;
		-*) ;;
		*) remote="$i"; break ;;
		esac
		((c++))
	done
	if [ -z "$remote" ]; then
		__gcomp_nl "$(__g_remotes)"
		return
	fi
	if [ $no_complete_refspec = 1 ]; then
		return
	fi
	[ "$remote" = "." ] && remote=
	case "$cur_" in
	*:*)
		case "$COMP_WORDBREAKS" in
		*:*) : great ;;
		*)   pfx="${cur_%%:*}:" ;;
		esac
		cur_="${cur_#*:}"
		lhs=0
		;;
	+*)
		pfx="+"
		cur_="${cur_#+}"
		;;
	esac
	case "$cmd" in
	fetch)
		if [ $lhs = 1 ]; then
			__g_complete_fetch_refspecs "$remote" "$pfx" "$cur_"
		else
			__g_complete_refs --pfx="$pfx" --cur="$cur_"
		fi
		;;
	pull|remote)
		if [ $lhs = 1 ]; then
			__g_complete_refs --remote="$remote" --pfx="$pfx" --cur="$cur_"
		else
			__g_complete_refs --pfx="$pfx" --cur="$cur_"
		fi
		;;
	push)
		if [ $lhs = 1 ]; then
			__g_complete_refs --pfx="$pfx" --cur="$cur_"
		else
			__g_complete_refs --remote="$remote" --pfx="$pfx" --cur="$cur_"
		fi
		;;
	esac
}

__g_complete_strategy ()
{
	__g_compute_merge_strategies
	case "$prev" in
	-s|--strategy)
		__gcomp "$__g_merge_strategies"
		return 0
		;;
	-X)
		__gcomp "$__g_merge_strategy_options"
		return 0
		;;
	esac
	case "$cur" in
	--strategy=*)
		__gcomp "$__g_merge_strategies" "" "${cur##--strategy=}"
		return 0
		;;
	--strategy-option=*)
		__gcomp "$__g_merge_strategy_options" "" "${cur##--strategy-option=}"
		return 0
		;;
	esac
	return 1
}

__g_all_commands=
__g_compute_all_commands ()
{
	test -n "$__g_all_commands" ||
	__g_all_commands=$(__g --list-cmds=main,others,alias,nohelpers)
}

# Lists all set config variables starting with the given section prefix,
# with the prefix removed.
__g_get_config_variables ()
{
	local section="$1" i IFS=$'\n'
	for i in $(__g config --name-only --get-regexp "^$section\..*"); do
		echo "${i#$section.}"
	done
}

__g_pretty_aliases ()
{
	__g_get_config_variables "pretty"
}

# __g_aliased_command requires 1 argument
__g_aliased_command ()
{
	local cur=$1 last list= word cmdline

	while [[ -n "$cur" ]]; do
		if [[ "$list" == *" $cur "* ]]; then
			# loop detected
			return
		fi

		cmdline=$(__g config --get "alias.$cur")
		list=" $cur $list"
		last=$cur
		cur=

		for word in $cmdline; do
			case "$word" in
			\!gk|gk)
				cur="gk"
				break
				;;
			\!*)	: shell command alias ;;
			-*)	: option ;;
			*=*)	: setting env ;;
			g)	: g itself ;;
			\(\))   : skip parens of shell function definition ;;
			{)	: skip start of shell helper function ;;
			:)	: skip null command ;;
			\'*)	: skip opening quote after sh -c ;;
			*)
				cur="${word%;}"
				break
			esac
		done
	done

	cur=$last
	if [[ "$cur" != "$1" ]]; then
		echo "$cur"
	fi
}

# Check whether one of the given words is present on the command line,
# and print the first word found.
#
# Usage: __g_find_on_cmdline [<option>]... "<wordlist>"
# --show-idx: Optionally show the index of the found word in the $words array.
__g_find_on_cmdline ()
{
	local word c="$__g_cmd_idx" show_idx

	while test $# -gt 1; do
		case "$1" in
		--show-idx)	show_idx=y ;;
		*)		return 1 ;;
		esac
		shift
	done
	local wordlist="$1"

	while [ $c -lt $cword ]; do
		for word in $wordlist; do
			if [ "$word" = "${words[c]}" ]; then
				if [ -n "${show_idx-}" ]; then
					echo "$c $word"
				else
					echo "$word"
				fi
				return
			fi
		done
		((c++))
	done
}

# Similar to __g_find_on_cmdline, except that it loops backwards and thus
# prints the *last* word found. Useful for finding which of two options that
# supersede each other came last, such as "--guess" and "--no-guess".
#
# Usage: __g_find_last_on_cmdline [<option>]... "<wordlist>"
# --show-idx: Optionally show the index of the found word in the $words array.
__g_find_last_on_cmdline ()
{
	local word c=$cword show_idx

	while test $# -gt 1; do
		case "$1" in
		--show-idx)	show_idx=y ;;
		*)		return 1 ;;
		esac
		shift
	done
	local wordlist="$1"

	while [ $c -gt "$__g_cmd_idx" ]; do
		((c--))
		for word in $wordlist; do
			if [ "$word" = "${words[c]}" ]; then
				if [ -n "$show_idx" ]; then
					echo "$c $word"
				else
					echo "$word"
				fi
				return
			fi
		done
	done
}

# Echo the value of an option set on the command line or config
#
# $1: short option name
# $2: long option name including =
# $3: list of possible values
# $4: config string (optional)
#
# example:
# result="$(__g_get_option_value "-d" "--do-something=" \
#     "yes no" "core.doSomething")"
#
# result is then either empty (no option set) or "yes" or "no"
#
# __g_get_option_value requires 3 arguments
__g_get_option_value ()
{
	local c short_opt long_opt val
	local result= values config_key word

	short_opt="$1"
	long_opt="$2"
	values="$3"
	config_key="$4"

	((c = $cword - 1))
	while [ $c -ge 0 ]; do
		word="${words[c]}"
		for val in $values; do
			if [ "$short_opt$val" = "$word" ] ||
			   [ "$long_opt$val"  = "$word" ]; then
				result="$val"
				break 2
			fi
		done
		((c--))
	done

	if [ -n "$config_key" ] && [ -z "$result" ]; then
		result="$(__g config "$config_key")"
	fi

	echo "$result"
}

__g_has_doubledash ()
{
	local c=1
	while [ $c -lt $cword ]; do
		if [ "--" = "${words[c]}" ]; then
			return 0
		fi
		((c++))
	done
	return 1
}

# Try to count non option arguments passed on the command line for the
# specified g command.
# When options are used, it is necessary to use the special -- option to
# tell the implementation were non option arguments begin.
# XXX this can not be improved, since options can appear everywhere, as
# an example:
#	g mv x -n y
#
# __g_count_arguments requires 1 argument: the g command executed.
__g_count_arguments ()
{
	local word i c=0

	# Skip "g" (first argument)
	for ((i=$__g_cmd_idx; i < ${#words[@]}; i++)); do
		word="${words[i]}"

		case "$word" in
			--)
				# Good; we can assume that the following are only non
				# option arguments.
				((c = 0))
				;;
			"$1")
				# Skip the specified g command and discard g
				# main options
				((c = 0))
				;;
			?*)
				((c++))
				;;
		esac
	done

	printf "%d" $c
}

__g_whitespacelist="nowarn warn error error-all fix"
__g_patchformat="mbox stg stg-series hg mboxrd"
__g_showcurrentpatch="diff raw"
__g_am_inprogress_options="--skip --continue --resolved --abort --quit --show-current-patch"
__g_quoted_cr="nowarn warn strip"

_g_am ()
{
	__g_find_repo_path
	if [ -d "$__g_repo_path"/rebase-apply ]; then
		__gcomp "$__g_am_inprogress_options"
		return
	fi
	case "$cur" in
	--whitespace=*)
		__gcomp "$__g_whitespacelist" "" "${cur##--whitespace=}"
		return
		;;
	--patch-format=*)
		__gcomp "$__g_patchformat" "" "${cur##--patch-format=}"
		return
		;;
	--show-current-patch=*)
		__gcomp "$__g_showcurrentpatch" "" "${cur##--show-current-patch=}"
		return
		;;
	--quoted-cr=*)
		__gcomp "$__g_quoted_cr" "" "${cur##--quoted-cr=}"
		return
		;;
	--*)
		__gcomp_builtin am "" \
			"$__g_am_inprogress_options"
		return
	esac
}

_g_apply ()
{
	case "$cur" in
	--whitespace=*)
		__gcomp "$__g_whitespacelist" "" "${cur##--whitespace=}"
		return
		;;
	--*)
		__gcomp_builtin apply
		return
	esac
}

_g_add ()
{
	case "$cur" in
	--chmod=*)
		__gcomp "+x -x" "" "${cur##--chmod=}"
		return
		;;
	--*)
		__gcomp_builtin add
		return
	esac

	local complete_opt="--others --modified --directory --no-empty-directory"
	if test -n "$(__g_find_on_cmdline "-u --update")"
	then
		complete_opt="--modified"
	fi
	__g_complete_index_file "$complete_opt"
}

_g_archive ()
{
	case "$cur" in
	--format=*)
		__gcomp "$(g archive --list)" "" "${cur##--format=}"
		return
		;;
	--remote=*)
		__gcomp_nl "$(__g_remotes)" "" "${cur##--remote=}"
		return
		;;
	--*)
		__gcomp_builtin archive "--format= --list --verbose --prefix= --worktree-attributes"
		return
		;;
	esac
	__g_complete_file
}

_g_bisect ()
{
	__g_has_doubledash && return

	__g_find_repo_path

	# If a bisection is in progress get the terms being used.
	local term_bad term_good
	if [ -f "$__g_repo_path"/BISECT_TERMS ]; then
		term_bad=$(__g bisect terms --term-bad)
		term_good=$(__g bisect terms --term-good)
	fi

	# We will complete any custom terms, but still always complete the
	# more usual bad/new/good/old because g bisect gives a good error
	# message if these are given when not in use, and that's better than
	# silent refusal to complete if the user is confused.
	#
	# We want to recognize 'view' but not complete it, because it overlaps
	# with 'visualize' too much and is just an alias for it.
	#
	local completable_subcommands="start bad new $term_bad good old $term_good terms skip reset visualize replay log run help"
	local all_subcommands="$completable_subcommands view"

	local subcommand="$(__g_find_on_cmdline "$all_subcommands")"

	if [ -z "$subcommand" ]; then
		__g_find_repo_path
		if [ -f "$__g_repo_path"/BISECT_START ]; then
			__gcomp "$completable_subcommands"
		else
			__gcomp "replay start"
		fi
		return
	fi

	case "$subcommand" in
	start)
		case "$cur" in
		--*)
			__gcomp "--first-parent --no-checkout --term-new --term-bad --term-old --term-good"
			return
			;;
		*)
			__g_complete_refs
			;;
		esac
		;;
	terms)
		__gcomp "--term-good --term-old --term-bad --term-new"
		return
		;;
	visualize|view)
		__g_complete_log_opts
		return
		;;
	bad|new|"$term_bad"|good|old|"$term_good"|reset|skip)
		__g_complete_refs
		;;
	*)
		;;
	esac
}

__g_ref_fieldlist="refname objecttype objectsize objectname upstream push HEAD symref"

_g_branch ()
{
	local i c="$__g_cmd_idx" only_local_ref="n" has_r="n"

	while [ $c -lt $cword ]; do
		i="${words[c]}"
		case "$i" in
		-d|-D|--delete|-m|-M|--move|-c|-C|--copy)
			only_local_ref="y" ;;
		-r|--remotes)
			has_r="y" ;;
		esac
		((c++))
	done

	case "$cur" in
	--set-upstream-to=*)
		__g_complete_refs --cur="${cur##--set-upstream-to=}"
		;;
	--*)
		__gcomp_builtin branch
		;;
	*)
		if [ $only_local_ref = "y" -a $has_r = "n" ]; then
			__gcomp_direct "$(__g_heads "" "$cur" " ")"
		else
			__g_complete_refs
		fi
		;;
	esac
}

_g_bundle ()
{
	local cmd="${words[__g_cmd_idx+1]}"
	case "$cword" in
	$((__g_cmd_idx+1)))
		__gcomp "create list-heads verify unbundle"
		;;
	$((__g_cmd_idx+2)))
		# looking for a file
		;;
	*)
		case "$cmd" in
			create)
				__g_complete_revlist
			;;
		esac
		;;
	esac
}

# Helper function to decide whether or not we should enable DWIM logic for
# g-switch and g-checkout.
#
# To decide between the following rules in decreasing priority order:
# - the last provided of "--guess" or "--no-guess" explicitly enable or
#   disable completion of DWIM logic respectively.
# - If checkout.guess is false, disable completion of DWIM logic.
# - If the --no-track option is provided, take this as a hint to disable the
#   DWIM completion logic
# - If GIT_COMPLETION_CHECKOUT_NO_GUESS is set, disable the DWIM completion
#   logic, as requested by the user.
# - Enable DWIM logic otherwise.
#
__g_checkout_default_dwim_mode ()
{
	local last_option dwim_opt="--dwim"

	if [ "${GIT_COMPLETION_CHECKOUT_NO_GUESS-}" = "1" ]; then
		dwim_opt=""
	fi

	# --no-track disables DWIM, but with lower priority than
	# --guess/--no-guess/checkout.guess
	if [ -n "$(__g_find_on_cmdline "--no-track")" ]; then
		dwim_opt=""
	fi

	# checkout.guess = false disables DWIM, but with lower priority than
	# --guess/--no-guess
	if [ "$(__g config --type=bool checkout.guess)" = "false" ]; then
		dwim_opt=""
	fi

	# Find the last provided --guess or --no-guess
	last_option="$(__g_find_last_on_cmdline "--guess --no-guess")"
	case "$last_option" in
		--guess)
			dwim_opt="--dwim"
			;;
		--no-guess)
			dwim_opt=""
			;;
	esac

	echo "$dwim_opt"
}

_g_checkout ()
{
	__g_has_doubledash && return

	local dwim_opt="$(__g_checkout_default_dwim_mode)"

	case "$prev" in
	-b|-B|--orphan)
		# Complete local branches (and DWIM branch
		# remote branch names) for an option argument
		# specifying a new branch name. This is for
		# convenience, assuming new branches are
		# possibly based on pre-existing branch names.
		__g_complete_refs $dwim_opt --mode="heads"
		return
		;;
	*)
		;;
	esac

	case "$cur" in
	--conflict=*)
		__gcomp "diff3 merge zdiff3" "" "${cur##--conflict=}"
		;;
	--*)
		__gcomp_builtin checkout
		;;
	*)
		# At this point, we've already handled special completion for
		# the arguments to -b/-B, and --orphan. There are 3 main
		# things left we can possibly complete:
		# 1) a start-point for -b/-B, -d/--detach, or --orphan
		# 2) a remote head, for --track
		# 3) an arbitrary reference, possibly including DWIM names
		#

		if [ -n "$(__g_find_on_cmdline "-b -B -d --detach --orphan")" ]; then
			__g_complete_refs --mode="refs"
		elif [ -n "$(__g_find_on_cmdline "-t --track")" ]; then
			__g_complete_refs --mode="remote-heads"
		else
			__g_complete_refs $dwim_opt --mode="refs"
		fi
		;;
	esac
}

__g_sequencer_inprogress_options="--continue --quit --abort --skip"

__g_cherry_pick_inprogress_options=$__g_sequencer_inprogress_options

_g_cherry_pick ()
{
	if __g_pseudoref_exists CHERRY_PICK_HEAD; then
		__gcomp "$__g_cherry_pick_inprogress_options"
		return
	fi

	__g_complete_strategy && return

	case "$cur" in
	--*)
		__gcomp_builtin cherry-pick "" \
			"$__g_cherry_pick_inprogress_options"
		;;
	*)
		__g_complete_refs
		;;
	esac
}

_g_clean ()
{
	case "$cur" in
	--*)
		__gcomp_builtin clean
		return
		;;
	esac

	# XXX should we check for -x option ?
	__g_complete_index_file "--others --directory"
}

_g_clone ()
{
	case "$prev" in
	-c|--config)
		__g_complete_config_variable_name_and_value
		return
		;;
	esac
	case "$cur" in
	--config=*)
		__g_complete_config_variable_name_and_value \
			--cur="${cur##--config=}"
		return
		;;
	--*)
		__gcomp_builtin clone
		return
		;;
	esac
}

__g_untracked_file_modes="all no normal"

__g_trailer_tokens ()
{
	__g config --name-only --get-regexp '^trailer\..*\.key$' | cut -d. -f 2- | rev | cut -d. -f2- | rev
}

_g_commit ()
{
	case "$prev" in
	-c|-C)
		__g_complete_refs
		return
		;;
	esac

	case "$cur" in
	--cleanup=*)
		__gcomp "default scissors strip verbatim whitespace
			" "" "${cur##--cleanup=}"
		return
		;;
	--reuse-message=*|--reedit-message=*|\
	--fixup=*|--squash=*)
		__g_complete_refs --cur="${cur#*=}"
		return
		;;
	--untracked-files=*)
		__gcomp "$__g_untracked_file_modes" "" "${cur##--untracked-files=}"
		return
		;;
	--trailer=*)
		__gcomp_nl "$(__g_trailer_tokens)" "" "${cur##--trailer=}" ":"
		return
		;;
	--*)
		__gcomp_builtin commit
		return
	esac

	if __g rev-parse --verify --quiet HEAD >/dev/null; then
		__g_complete_index_file "--committable"
	else
		# This is the first commit
		__g_complete_index_file "--cached"
	fi
}

_g_describe ()
{
	case "$cur" in
	--*)
		__gcomp_builtin describe
		return
	esac
	__g_complete_refs
}

__g_diff_algorithms="myers minimal patience histogram"

__g_diff_submodule_formats="diff log short"

__g_color_moved_opts="no default plain blocks zebra dimmed-zebra"

__g_color_moved_ws_opts="no ignore-space-at-eol ignore-space-change
			ignore-all-space allow-indentation-change"

__g_ws_error_highlight_opts="context old new all default"

# Options for the diff machinery (diff, log, show, stash, range-diff, ...)
__g_diff_common_options="--stat --numstat --shortstat --summary
			--patch-with-stat --name-only --name-status --color
			--no-color --color-words --no-renames --check
			--color-moved --color-moved= --no-color-moved
			--color-moved-ws= --no-color-moved-ws
			--full-index --binary --abbrev --diff-filter=
			--find-copies --find-object --find-renames
			--no-relative --relative
			--find-copies-harder --ignore-cr-at-eol
			--text --ignore-space-at-eol --ignore-space-change
			--ignore-all-space --ignore-blank-lines --exit-code
			--quiet --ext-diff --no-ext-diff --unified=
			--no-prefix --src-prefix= --dst-prefix=
			--inter-hunk-context= --function-context
			--patience --histogram --minimal
			--raw --word-diff --word-diff-regex=
			--dirstat --dirstat= --dirstat-by-file
			--dirstat-by-file= --cumulative
			--diff-algorithm= --default-prefix
			--submodule --submodule= --ignore-submodules
			--indent-heuristic --no-indent-heuristic
			--textconv --no-textconv --break-rewrites
			--patch --no-patch --cc --combined-all-paths
			--anchored= --compact-summary --ignore-matching-lines=
			--irreversible-delete --line-prefix --no-stat
			--output= --output-indicator-context=
			--output-indicator-new= --output-indicator-old=
			--ws-error-highlight=
			--pickaxe-all --pickaxe-regex --patch-with-raw
"

# Options for diff/difftool
__g_diff_difftool_options="--cached --staged
			--base --ours --theirs --no-index --merge-base
			--ita-invisible-in-index --ita-visible-in-index
			$__g_diff_common_options"

_g_diff ()
{
	__g_has_doubledash && return

	case "$cur" in
	--diff-algorithm=*)
		__gcomp "$__g_diff_algorithms" "" "${cur##--diff-algorithm=}"
		return
		;;
	--submodule=*)
		__gcomp "$__g_diff_submodule_formats" "" "${cur##--submodule=}"
		return
		;;
	--color-moved=*)
		__gcomp "$__g_color_moved_opts" "" "${cur##--color-moved=}"
		return
		;;
	--color-moved-ws=*)
		__gcomp "$__g_color_moved_ws_opts" "" "${cur##--color-moved-ws=}"
		return
		;;
	--ws-error-highlight=*)
		__gcomp "$__g_ws_error_highlight_opts" "" "${cur##--ws-error-highlight=}"
		return
		;;
	--*)
		__gcomp "$__g_diff_difftool_options"
		return
		;;
	esac
	__g_complete_revlist_file
}

__g_mergetools_common="diffuse diffmerge ecmerge emerge kdiff3 meld opendiff
			tkdiff vimdiff nvimdiff gvimdiff xxdiff araxis p4merge
			bc codecompare smerge
"

_g_difftool ()
{
	__g_has_doubledash && return

	case "$cur" in
	--tool=*)
		__gcomp "$__g_mergetools_common kompare" "" "${cur##--tool=}"
		return
		;;
	--*)
		__gcomp_builtin difftool "$__g_diff_difftool_options"
		return
		;;
	esac
	__g_complete_revlist_file
}

__g_fetch_recurse_submodules="yes on-demand no"

_g_fetch ()
{
	case "$cur" in
	--recurse-submodules=*)
		__gcomp "$__g_fetch_recurse_submodules" "" "${cur##--recurse-submodules=}"
		return
		;;
	--filter=*)
		__gcomp "blob:none blob:limit= sparse:oid=" "" "${cur##--filter=}"
		return
		;;
	--*)
		__gcomp_builtin fetch
		return
		;;
	esac
	__g_complete_remote_or_refspec
}

__g_format_patch_extra_options="
	--full-index --not --all --no-prefix --src-prefix=
	--dst-prefix= --notes
"

_g_format_patch ()
{
	case "$cur" in
	--thread=*)
		__gcomp "
			deep shallow
			" "" "${cur##--thread=}"
		return
		;;
	--base=*|--interdiff=*|--range-diff=*)
		__g_complete_refs --cur="${cur#--*=}"
		return
		;;
	--*)
		__gcomp_builtin format-patch "$__g_format_patch_extra_options"
		return
		;;
	esac
	__g_complete_revlist
}

_g_fsck ()
{
	case "$cur" in
	--*)
		__gcomp_builtin fsck
		return
		;;
	esac
}

_g_gk ()
{
	__gk_main
}

# Lists matching symbol names from a tag (as in ctags) file.
# 1: List symbol names matching this word.
# 2: The tag file to list symbol names from.
# 3: A prefix to be added to each listed symbol name (optional).
# 4: A suffix to be appended to each listed symbol name (optional).
__g_match_ctag () {
	awk -v pfx="${3-}" -v sfx="${4-}" "
		/^${1//\//\\/}/ { print pfx \$1 sfx }
		" "$2"
}

# Complete symbol names from a tag file.
# Usage: __g_complete_symbol [<option>]...
# --tags=<file>: The tag file to list symbol names from instead of the
#                default "tags".
# --pfx=<prefix>: A prefix to be added to each symbol name.
# --cur=<word>: The current symbol name to be completed.  Defaults to
#               the current word to be completed.
# --sfx=<suffix>: A suffix to be appended to each symbol name instead
#                 of the default space.
__g_complete_symbol () {
	local tags=tags pfx="" cur_="${cur-}" sfx=" "

	while test $# != 0; do
		case "$1" in
		--tags=*)	tags="${1##--tags=}" ;;
		--pfx=*)	pfx="${1##--pfx=}" ;;
		--cur=*)	cur_="${1##--cur=}" ;;
		--sfx=*)	sfx="${1##--sfx=}" ;;
		*)		return 1 ;;
		esac
		shift
	done

	if test -r "$tags"; then
		__gcomp_direct "$(__g_match_ctag "$cur_" "$tags" "$pfx" "$sfx")"
	fi
}

_g_grep ()
{
	__g_has_doubledash && return

	case "$cur" in
	--*)
		__gcomp_builtin grep
		return
		;;
	esac

	case "$cword,$prev" in
	$((__g_cmd_idx+1)),*|*,-*)
		__g_complete_symbol && return
		;;
	esac

	__g_complete_refs
}

_g_help ()
{
	case "$cur" in
	--*)
		__gcomp_builtin help
		return
		;;
	esac
	if test -n "${GIT_TESTING_ALL_COMMAND_LIST-}"
	then
		__gcomp "$GIT_TESTING_ALL_COMMAND_LIST $(__g --list-cmds=alias,list-guide) gk"
	else
		__gcomp "$(__g --list-cmds=main,nohelpers,alias,list-guide) gk"
	fi
}

_g_init ()
{
	case "$cur" in
	--shared=*)
		__gcomp "
			false true umask group all world everybody
			" "" "${cur##--shared=}"
		return
		;;
	--*)
		__gcomp_builtin init
		return
		;;
	esac
}

_g_ls_files ()
{
	case "$cur" in
	--*)
		__gcomp_builtin ls-files
		return
		;;
	esac

	# XXX ignore options like --modified and always suggest all cached
	# files.
	__g_complete_index_file "--cached"
}

_g_ls_remote ()
{
	case "$cur" in
	--*)
		__gcomp_builtin ls-remote
		return
		;;
	esac
	__gcomp_nl "$(__g_remotes)"
}

_g_ls_tree ()
{
	case "$cur" in
	--*)
		__gcomp_builtin ls-tree
		return
		;;
	esac

	__g_complete_file
}

# Options that go well for log, shortlog and gk
__g_log_common_options="
	--not --all
	--branches --tags --remotes
	--first-parent --merges --no-merges
	--max-count=
	--max-age= --since= --after=
	--min-age= --until= --before=
	--min-parents= --max-parents=
	--no-min-parents --no-max-parents
	--alternate-refs --ancestry-path
	--author-date-order --basic-regexp
	--bisect --boundary --exclude-first-parent-only
	--exclude-hidden --extended-regexp
	--fixed-strings --grep-reflog
	--ignore-missing --left-only --perl-regexp
	--reflog --regexp-ignore-case --remove-empty
	--right-only --show-linear-break
	--show-notes-by-default --show-pulls
	--since-as-filter --single-worktree
"
# Options that go well for log and gk (not shortlog)
__g_log_gk_options="
	--dense --sparse --full-history
	--simplify-merges --simplify-by-decoration
	--left-right --notes --no-notes
"
# Options that go well for log and shortlog (not gk)
__g_log_shortlog_options="
	--author= --committer= --grep=
	--all-match --invert-grep
"
# Options accepted by log and show
__g_log_show_options="
	--diff-merges --diff-merges= --no-diff-merges --dd --remerge-diff
	--encoding=
"

__g_diff_merges_opts="off none on first-parent 1 separate m combined c dense-combined cc remerge r"

__g_log_pretty_formats="oneline short medium full fuller reference email raw format: tformat: mboxrd"
__g_log_date_formats="relative iso8601 iso8601-strict rfc2822 short local default human raw unix auto: format:"

# Complete porcelain (i.e. not g-rev-list) options and at least some
# option arguments accepted by g-log.  Note that this same set of options
# are also accepted by some other g commands besides g-log.
__g_complete_log_opts ()
{
	COMPREPLY=()

	local merge=""
	if __g_pseudoref_exists MERGE_HEAD; then
		merge="--merge"
	fi
	case "$prev,$cur" in
	-L,:*:*)
		return	# fall back to Bash filename completion
		;;
	-L,:*)
		__g_complete_symbol --cur="${cur#:}" --sfx=":"
		return
		;;
	-G,*|-S,*)
		__g_complete_symbol
		return
		;;
	esac
	case "$cur" in
	--pretty=*|--format=*)
		__gcomp "$__g_log_pretty_formats $(__g_pretty_aliases)
			" "" "${cur#*=}"
		return
		;;
	--date=*)
		__gcomp "$__g_log_date_formats" "" "${cur##--date=}"
		return
		;;
	--decorate=*)
		__gcomp "full short no" "" "${cur##--decorate=}"
		return
		;;
	--diff-algorithm=*)
		__gcomp "$__g_diff_algorithms" "" "${cur##--diff-algorithm=}"
		return
		;;
	--submodule=*)
		__gcomp "$__g_diff_submodule_formats" "" "${cur##--submodule=}"
		return
		;;
	--ws-error-highlight=*)
		__gcomp "$__g_ws_error_highlight_opts" "" "${cur##--ws-error-highlight=}"
		return
		;;
	--no-walk=*)
		__gcomp "sorted unsorted" "" "${cur##--no-walk=}"
		return
		;;
	--diff-merges=*)
                __gcomp "$__g_diff_merges_opts" "" "${cur##--diff-merges=}"
                return
                ;;
	--*)
		__gcomp "
			$__g_log_common_options
			$__g_log_shortlog_options
			$__g_log_gk_options
			$__g_log_show_options
			--root --topo-order --date-order --reverse
			--follow --full-diff
			--abbrev-commit --no-abbrev-commit --abbrev=
			--relative-date --date=
			--pretty= --format= --oneline
			--show-signature
			--cherry-mark
			--cherry-pick
			--graph
			--decorate --decorate= --no-decorate
			--walk-reflogs
			--no-walk --no-walk= --do-walk
			--parents --children
			--expand-tabs --expand-tabs= --no-expand-tabs
			--clear-decorations --decorate-refs=
			--decorate-refs-exclude=
			$merge
			$__g_diff_common_options
			"
		return
		;;
	-L:*:*)
		return	# fall back to Bash filename completion
		;;
	-L:*)
		__g_complete_symbol --cur="${cur#-L:}" --sfx=":"
		return
		;;
	-G*)
		__g_complete_symbol --pfx="-G" --cur="${cur#-G}"
		return
		;;
	-S*)
		__g_complete_symbol --pfx="-S" --cur="${cur#-S}"
		return
		;;
	esac
}

_g_log ()
{
	__g_has_doubledash && return
	__g_find_repo_path

	__g_complete_log_opts
        [ ${#COMPREPLY[@]} -eq 0 ] || return

	__g_complete_revlist
}

_g_merge ()
{
	__g_complete_strategy && return

	case "$cur" in
	--*)
		__gcomp_builtin merge
		return
	esac
	__g_complete_refs
}

_g_mergetool ()
{
	case "$cur" in
	--tool=*)
		__gcomp "$__g_mergetools_common tortoisemerge" "" "${cur##--tool=}"
		return
		;;
	--*)
		__gcomp "--tool= --prompt --no-prompt --gui --no-gui"
		return
		;;
	esac
}

_g_merge_base ()
{
	case "$cur" in
	--*)
		__gcomp_builtin merge-base
		return
		;;
	esac
	__g_complete_refs
}

_g_mv ()
{
	case "$cur" in
	--*)
		__gcomp_builtin mv
		return
		;;
	esac

	if [ $(__g_count_arguments "mv") -gt 0 ]; then
		# We need to show both cached and untracked files (including
		# empty directories) since this may not be the last argument.
		__g_complete_index_file "--cached --others --directory"
	else
		__g_complete_index_file "--cached"
	fi
}

_g_notes ()
{
	local subcommands='add append copy edit get-ref list merge prune remove show'
	local subcommand="$(__g_find_on_cmdline "$subcommands")"

	case "$subcommand,$cur" in
	,--*)
		__gcomp_builtin notes
		;;
	,*)
		case "$prev" in
		--ref)
			__g_complete_refs
			;;
		*)
			__gcomp "$subcommands --ref"
			;;
		esac
		;;
	*,--reuse-message=*|*,--reedit-message=*)
		__g_complete_refs --cur="${cur#*=}"
		;;
	*,--*)
		__gcomp_builtin notes_$subcommand
		;;
	prune,*|get-ref,*)
		# this command does not take a ref, do not complete it
		;;
	*)
		case "$prev" in
		-m|-F)
			;;
		*)
			__g_complete_refs
			;;
		esac
		;;
	esac
}

_g_pull ()
{
	__g_complete_strategy && return

	case "$cur" in
	--recurse-submodules=*)
		__gcomp "$__g_fetch_recurse_submodules" "" "${cur##--recurse-submodules=}"
		return
		;;
	--*)
		__gcomp_builtin pull

		return
		;;
	esac
	__g_complete_remote_or_refspec
}

__g_push_recurse_submodules="check on-demand only"

__g_complete_force_with_lease ()
{
	local cur_=$1

	case "$cur_" in
	--*=)
		;;
	*:*)
		__g_complete_refs --cur="${cur_#*:}"
		;;
	*)
		__g_complete_refs --cur="$cur_"
		;;
	esac
}

_g_push ()
{
	case "$prev" in
	--repo)
		__gcomp_nl "$(__g_remotes)"
		return
		;;
	--recurse-submodules)
		__gcomp "$__g_push_recurse_submodules"
		return
		;;
	esac
	case "$cur" in
	--repo=*)
		__gcomp_nl "$(__g_remotes)" "" "${cur##--repo=}"
		return
		;;
	--recurse-submodules=*)
		__gcomp "$__g_push_recurse_submodules" "" "${cur##--recurse-submodules=}"
		return
		;;
	--force-with-lease=*)
		__g_complete_force_with_lease "${cur##--force-with-lease=}"
		return
		;;
	--*)
		__gcomp_builtin push
		return
		;;
	esac
	__g_complete_remote_or_refspec
}

_g_range_diff ()
{
	case "$cur" in
	--*)
		__gcomp "
			--creation-factor= --no-dual-color
			$__g_diff_common_options
		"
		return
		;;
	esac
	__g_complete_revlist
}

__g_rebase_inprogress_options="--continue --skip --abort --quit --show-current-patch"
__g_rebase_interactive_inprogress_options="$__g_rebase_inprogress_options --edit-todo"

_g_rebase ()
{
	__g_find_repo_path
	if [ -f "$__g_repo_path"/rebase-merge/interactive ]; then
		__gcomp "$__g_rebase_interactive_inprogress_options"
		return
	elif [ -d "$__g_repo_path"/rebase-apply ] || \
	     [ -d "$__g_repo_path"/rebase-merge ]; then
		__gcomp "$__g_rebase_inprogress_options"
		return
	fi
	__g_complete_strategy && return
	case "$cur" in
	--whitespace=*)
		__gcomp "$__g_whitespacelist" "" "${cur##--whitespace=}"
		return
		;;
	--onto=*)
		__g_complete_refs --cur="${cur##--onto=}"
		return
		;;
	--*)
		__gcomp_builtin rebase "" \
			"$__g_rebase_interactive_inprogress_options"

		return
	esac
	__g_complete_refs
}

_g_reflog ()
{
	local subcommands subcommand

	__g_resolve_builtins "reflog"

	subcommands="$___g_resolved_builtins"
	subcommand="$(__g_find_subcommand "$subcommands" "show")"

	case "$subcommand,$cur" in
	show,--*)
		__gcomp "
			$__g_log_common_options
			"
		return
		;;
	$subcommand,--*)
		__gcomp_builtin "reflog_$subcommand"
		return
		;;
	esac

	__g_complete_refs

	if [ $((cword - __g_cmd_idx)) -eq 1 ]; then
		__gcompappend "$subcommands" "" "$cur" " "
	fi
}

__g_send_email_confirm_options="always never auto cc compose"
__g_send_email_suppresscc_options="author self cc bodycc sob cccmd body all"

_g_send_email ()
{
	case "$prev" in
	--to|--cc|--bcc|--from)
		__gcomp "$(__g send-email --dump-aliases)"
		return
		;;
	esac

	case "$cur" in
	--confirm=*)
		__gcomp "
			$__g_send_email_confirm_options
			" "" "${cur##--confirm=}"
		return
		;;
	--suppress-cc=*)
		__gcomp "
			$__g_send_email_suppresscc_options
			" "" "${cur##--suppress-cc=}"

		return
		;;
	--smtp-encryption=*)
		__gcomp "ssl tls" "" "${cur##--smtp-encryption=}"
		return
		;;
	--thread=*)
		__gcomp "
			deep shallow
			" "" "${cur##--thread=}"
		return
		;;
	--to=*|--cc=*|--bcc=*|--from=*)
		__gcomp "$(__g send-email --dump-aliases)" "" "${cur#--*=}"
		return
		;;
	--*)
		__gcomp_builtin send-email "$__g_format_patch_extra_options"
		return
		;;
	esac
	__g_complete_revlist
}

_g_stage ()
{
	_g_add
}

_g_status ()
{
	local complete_opt
	local untracked_state

	case "$cur" in
	--ignore-submodules=*)
		__gcomp "none untracked dirty all" "" "${cur##--ignore-submodules=}"
		return
		;;
	--untracked-files=*)
		__gcomp "$__g_untracked_file_modes" "" "${cur##--untracked-files=}"
		return
		;;
	--column=*)
		__gcomp "
			always never auto column row plain dense nodense
			" "" "${cur##--column=}"
		return
		;;
	--*)
		__gcomp_builtin status
		return
		;;
	esac

	untracked_state="$(__g_get_option_value "-u" "--untracked-files=" \
		"$__g_untracked_file_modes" "status.showUntrackedFiles")"

	case "$untracked_state" in
	no)
		# --ignored option does not matter
		complete_opt=
		;;
	all|normal|*)
		complete_opt="--cached --directory --no-empty-directory --others"

		if [ -n "$(__g_find_on_cmdline "--ignored")" ]; then
			complete_opt="$complete_opt --ignored --exclude=*"
		fi
		;;
	esac

	__g_complete_index_file "$complete_opt"
}

_g_switch ()
{
	local dwim_opt="$(__g_checkout_default_dwim_mode)"

	case "$prev" in
	-c|-C|--orphan)
		# Complete local branches (and DWIM branch
		# remote branch names) for an option argument
		# specifying a new branch name. This is for
		# convenience, assuming new branches are
		# possibly based on pre-existing branch names.
		__g_complete_refs $dwim_opt --mode="heads"
		return
		;;
	*)
		;;
	esac

	case "$cur" in
	--conflict=*)
		__gcomp "diff3 merge zdiff3" "" "${cur##--conflict=}"
		;;
	--*)
		__gcomp_builtin switch
		;;
	*)
		# Unlike in g checkout, g switch --orphan does not take
		# a start point. Thus we really have nothing to complete after
		# the branch name.
		if [ -n "$(__g_find_on_cmdline "--orphan")" ]; then
			return
		fi

		# At this point, we've already handled special completion for
		# -c/-C, and --orphan. There are 3 main things left to
		# complete:
		# 1) a start-point for -c/-C or -d/--detach
		# 2) a remote head, for --track
		# 3) a branch name, possibly including DWIM remote branches

		if [ -n "$(__g_find_on_cmdline "-c -C -d --detach")" ]; then
			__g_complete_refs --mode="refs"
		elif [ -n "$(__g_find_on_cmdline "-t --track")" ]; then
			__g_complete_refs --mode="remote-heads"
		else
			__g_complete_refs $dwim_opt --mode="heads"
		fi
		;;
	esac
}

__g_config_get_set_variables ()
{
	local prevword word config_file= c=$cword
	while [ $c -gt "$__g_cmd_idx" ]; do
		word="${words[c]}"
		case "$word" in
		--system|--global|--local|--file=*)
			config_file="$word"
			break
			;;
		-f|--file)
			config_file="$word $prevword"
			break
			;;
		esac
		prevword=$word
		c=$((--c))
	done

	__g config $config_file --name-only --list
}

__g_config_vars=
__g_compute_config_vars ()
{
	test -n "$__g_config_vars" ||
	__g_config_vars="$(g help --config-for-completion)"
}

__g_config_vars_all=
__g_compute_config_vars_all ()
{
	test -n "$__g_config_vars_all" ||
	__g_config_vars_all="$(g --no-pager help --config)"
}

__g_compute_first_level_config_vars_for_section ()
{
	local section="$1"
	__g_compute_config_vars
	local this_section="__g_first_level_config_vars_for_section_${section}"
	test -n "${!this_section}" ||
	printf -v "__g_first_level_config_vars_for_section_${section}" %s \
		"$(echo "$__g_config_vars" | awk -F. "/^${section}\.[a-z]/ { print \$2 }")"
}

__g_compute_second_level_config_vars_for_section ()
{
	local section="$1"
	__g_compute_config_vars_all
	local this_section="__g_second_level_config_vars_for_section_${section}"
	test -n "${!this_section}" ||
	printf -v "__g_second_level_config_vars_for_section_${section}" %s \
		"$(echo "$__g_config_vars_all" | awk -F. "/^${section}\.</ { print \$3 }")"
}

__g_config_sections=
__g_compute_config_sections ()
{
	test -n "$__g_config_sections" ||
	__g_config_sections="$(g help --config-sections-for-completion)"
}

# Completes possible values of various configuration variables.
#
# Usage: __g_complete_config_variable_value [<option>]...
# --varname=<word>: The name of the configuration variable whose value is
#                   to be completed.  Defaults to the previous word on the
#                   command line.
# --cur=<word>: The current value to be completed.  Defaults to the current
#               word to be completed.
__g_complete_config_variable_value ()
{
	local varname="$prev" cur_="$cur"

	while test $# != 0; do
		case "$1" in
		--varname=*)	varname="${1##--varname=}" ;;
		--cur=*)	cur_="${1##--cur=}" ;;
		*)		return 1 ;;
		esac
		shift
	done

	if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
		varname="${varname,,}"
	else
		varname="$(echo "$varname" |tr A-Z a-z)"
	fi

	case "$varname" in
	branch.*.remote|branch.*.pushremote)
		__gcomp_nl "$(__g_remotes)" "" "$cur_"
		return
		;;
	branch.*.merge)
		__g_complete_refs --cur="$cur_"
		return
		;;
	branch.*.rebase)
		__gcomp "false true merges interactive" "" "$cur_"
		return
		;;
	remote.pushdefault)
		__gcomp_nl "$(__g_remotes)" "" "$cur_"
		return
		;;
	remote.*.fetch)
		local remote="${varname#remote.}"
		remote="${remote%.fetch}"
		if [ -z "$cur_" ]; then
			__gcomp_nl "refs/heads/" "" "" ""
			return
		fi
		__gcomp_nl "$(__g_refs_remotes "$remote")" "" "$cur_"
		return
		;;
	remote.*.push)
		local remote="${varname#remote.}"
		remote="${remote%.push}"
		__gcomp_nl "$(__g for-each-ref \
			--format='%(refname):%(refname)' refs/heads)" "" "$cur_"
		return
		;;
	pull.twohead|pull.octopus)
		__g_compute_merge_strategies
		__gcomp "$__g_merge_strategies" "" "$cur_"
		return
		;;
	color.pager)
		__gcomp "false true" "" "$cur_"
		return
		;;
	color.*.*)
		__gcomp "
			normal black red green yellow blue magenta cyan white
			bold dim ul blink reverse
			" "" "$cur_"
		return
		;;
	color.*)
		__gcomp "false true always never auto" "" "$cur_"
		return
		;;
	diff.submodule)
		__gcomp "$__g_diff_submodule_formats" "" "$cur_"
		return
		;;
	help.format)
		__gcomp "man info web html" "" "$cur_"
		return
		;;
	log.date)
		__gcomp "$__g_log_date_formats" "" "$cur_"
		return
		;;
	sendemail.aliasfiletype)
		__gcomp "mutt mailrc pine elm gnus" "" "$cur_"
		return
		;;
	sendemail.confirm)
		__gcomp "$__g_send_email_confirm_options" "" "$cur_"
		return
		;;
	sendemail.suppresscc)
		__gcomp "$__g_send_email_suppresscc_options" "" "$cur_"
		return
		;;
	sendemail.transferencoding)
		__gcomp "7bit 8bit quoted-printable base64" "" "$cur_"
		return
		;;
	*.*)
		return
		;;
	esac
}

# Completes configuration sections, subsections, variable names.
#
# Usage: __g_complete_config_variable_name [<option>]...
# --cur=<word>: The current configuration section/variable name to be
#               completed.  Defaults to the current word to be completed.
# --sfx=<suffix>: A suffix to be appended to each fully completed
#                 configuration variable name (but not to sections or
#                 subsections) instead of the default space.
__g_complete_config_variable_name ()
{
	local cur_="$cur" sfx

	while test $# != 0; do
		case "$1" in
		--cur=*)	cur_="${1##--cur=}" ;;
		--sfx=*)	sfx="${1##--sfx=}" ;;
		*)		return 1 ;;
		esac
		shift
	done

	case "$cur_" in
	branch.*.*|guitool.*.*|difftool.*.*|man.*.*|mergetool.*.*|remote.*.*|submodule.*.*|url.*.*)
		local pfx="${cur_%.*}."
		cur_="${cur_##*.}"
		local section="${pfx%.*.}"
		__g_compute_second_level_config_vars_for_section "${section}"
		local this_section="__g_second_level_config_vars_for_section_${section}"
		__gcomp "${!this_section}" "$pfx" "$cur_" "$sfx"
		return
		;;
	branch.*)
		local pfx="${cur_%.*}."
		cur_="${cur_#*.}"
		local section="${pfx%.}"
		__gcomp_direct "$(__g_heads "$pfx" "$cur_" ".")"
		__g_compute_first_level_config_vars_for_section "${section}"
		local this_section="__g_first_level_config_vars_for_section_${section}"
		__gcomp_nl_append "${!this_section}" "$pfx" "$cur_" "${sfx:- }"
		return
		;;
	pager.*)
		local pfx="${cur_%.*}."
		cur_="${cur_#*.}"
		__g_compute_all_commands
		__gcomp_nl "$__g_all_commands" "$pfx" "$cur_" "${sfx:- }"
		return
		;;
	remote.*)
		local pfx="${cur_%.*}."
		cur_="${cur_#*.}"
		local section="${pfx%.}"
		__gcomp_nl "$(__g_remotes)" "$pfx" "$cur_" "."
		__g_compute_first_level_config_vars_for_section "${section}"
		local this_section="__g_first_level_config_vars_for_section_${section}"
		__gcomp_nl_append "${!this_section}" "$pfx" "$cur_" "${sfx:- }"
		return
		;;
	submodule.*)
		local pfx="${cur_%.*}."
		cur_="${cur_#*.}"
		local section="${pfx%.}"
		__gcomp_nl "$(__g config -f "$(__g rev-parse --show-toplevel)/.gmodules" --get-regexp 'submodule.*.path' | awk -F. '{print $2}')" "$pfx" "$cur_" "."
		__g_compute_first_level_config_vars_for_section "${section}"
		local this_section="__g_first_level_config_vars_for_section_${section}"
		__gcomp_nl_append "${!this_section}" "$pfx" "$cur_" "${sfx:- }"
		return
		;;
	*.*)
		__g_compute_config_vars
		__gcomp "$__g_config_vars" "" "$cur_" "$sfx"
		;;
	*)
		__g_compute_config_sections
		__gcomp "$__g_config_sections" "" "$cur_" "."
		;;
	esac
}

# Completes '='-separated configuration sections/variable names and values
# for 'g -c section.name=value'.
#
# Usage: __g_complete_config_variable_name_and_value [<option>]...
# --cur=<word>: The current configuration section/variable name/value to be
#               completed. Defaults to the current word to be completed.
__g_complete_config_variable_name_and_value ()
{
	local cur_="$cur"

	while test $# != 0; do
		case "$1" in
		--cur=*)	cur_="${1##--cur=}" ;;
		*)		return 1 ;;
		esac
		shift
	done

	case "$cur_" in
	*=*)
		__g_complete_config_variable_value \
			--varname="${cur_%%=*}" --cur="${cur_#*=}"
		;;
	*)
		__g_complete_config_variable_name --cur="$cur_" --sfx='='
		;;
	esac
}

_g_config ()
{
	local subcommands subcommand

	__g_resolve_builtins "config"

	subcommands="$___g_resolved_builtins"
	subcommand="$(__g_find_subcommand "$subcommands")"

	if [ -z "$subcommand" ]
	then
		__gcomp "$subcommands"
		return
	fi

	case "$cur" in
	--*)
		__gcomp_builtin "config_$subcommand"
		return
		;;
	esac

	case "$subcommand" in
	get)
		__gcomp_nl "$(__g_config_get_set_variables)"
		;;
	set)
		case "$prev" in
		*.*)
			__g_complete_config_variable_value
			;;
		*)
			__g_complete_config_variable_name
			;;
		esac
		;;
	unset)
		__gcomp_nl "$(__g_config_get_set_variables)"
		;;
	esac
}

_g_remote ()
{
	local subcommands="
		add rename remove set-head set-branches
		get-url set-url show prune update
		"
	local subcommand="$(__g_find_on_cmdline "$subcommands")"
	if [ -z "$subcommand" ]; then
		case "$cur" in
		--*)
			__gcomp_builtin remote
			;;
		*)
			__gcomp "$subcommands"
			;;
		esac
		return
	fi

	case "$subcommand,$cur" in
	add,--*)
		__gcomp_builtin remote_add
		;;
	add,*)
		;;
	set-head,--*)
		__gcomp_builtin remote_set-head
		;;
	set-branches,--*)
		__gcomp_builtin remote_set-branches
		;;
	set-head,*|set-branches,*)
		__g_complete_remote_or_refspec
		;;
	update,--*)
		__gcomp_builtin remote_update
		;;
	update,*)
		__gcomp "$(__g_remotes) $(__g_get_config_variables "remotes")"
		;;
	set-url,--*)
		__gcomp_builtin remote_set-url
		;;
	get-url,--*)
		__gcomp_builtin remote_get-url
		;;
	prune,--*)
		__gcomp_builtin remote_prune
		;;
	*)
		__gcomp_nl "$(__g_remotes)"
		;;
	esac
}

_g_replace ()
{
	case "$cur" in
	--format=*)
		__gcomp "short medium long" "" "${cur##--format=}"
		return
		;;
	--*)
		__gcomp_builtin replace
		return
		;;
	esac
	__g_complete_refs
}

_g_rerere ()
{
	local subcommands="clear forget diff remaining status gc"
	local subcommand="$(__g_find_on_cmdline "$subcommands")"
	if test -z "$subcommand"
	then
		__gcomp "$subcommands"
		return
	fi
}

_g_reset ()
{
	__g_has_doubledash && return

	case "$cur" in
	--*)
		__gcomp_builtin reset
		return
		;;
	esac
	__g_complete_refs
}

_g_restore ()
{
	case "$prev" in
	-s)
		__g_complete_refs
		return
		;;
	esac

	case "$cur" in
	--conflict=*)
		__gcomp "diff3 merge zdiff3" "" "${cur##--conflict=}"
		;;
	--source=*)
		__g_complete_refs --cur="${cur##--source=}"
		;;
	--*)
		__gcomp_builtin restore
		;;
	*)
		if __g_pseudoref_exists HEAD; then
			__g_complete_index_file "--modified"
		fi
	esac
}

__g_revert_inprogress_options=$__g_sequencer_inprogress_options

_g_revert ()
{
	if __g_pseudoref_exists REVERT_HEAD; then
		__gcomp "$__g_revert_inprogress_options"
		return
	fi
	__g_complete_strategy && return
	case "$cur" in
	--*)
		__gcomp_builtin revert "" \
			"$__g_revert_inprogress_options"
		return
		;;
	esac
	__g_complete_refs
}

_g_rm ()
{
	case "$cur" in
	--*)
		__gcomp_builtin rm
		return
		;;
	esac

	__g_complete_index_file "--cached"
}

_g_shortlog ()
{
	__g_has_doubledash && return

	case "$cur" in
	--*)
		__gcomp "
			$__g_log_common_options
			$__g_log_shortlog_options
			--numbered --summary --email
			"
		return
		;;
	esac
	__g_complete_revlist
}

_g_show ()
{
	__g_has_doubledash && return

	case "$cur" in
	--pretty=*|--format=*)
		__gcomp "$__g_log_pretty_formats $(__g_pretty_aliases)
			" "" "${cur#*=}"
		return
		;;
	--diff-algorithm=*)
		__gcomp "$__g_diff_algorithms" "" "${cur##--diff-algorithm=}"
		return
		;;
	--submodule=*)
		__gcomp "$__g_diff_submodule_formats" "" "${cur##--submodule=}"
		return
		;;
	--color-moved=*)
		__gcomp "$__g_color_moved_opts" "" "${cur##--color-moved=}"
		return
		;;
	--color-moved-ws=*)
		__gcomp "$__g_color_moved_ws_opts" "" "${cur##--color-moved-ws=}"
		return
		;;
	--ws-error-highlight=*)
		__gcomp "$__g_ws_error_highlight_opts" "" "${cur##--ws-error-highlight=}"
		return
		;;
	--diff-merges=*)
                __gcomp "$__g_diff_merges_opts" "" "${cur##--diff-merges=}"
                return
                ;;
	--*)
		__gcomp "--pretty= --format= --abbrev-commit --no-abbrev-commit
			--oneline --show-signature
			--expand-tabs --expand-tabs= --no-expand-tabs
			$__g_log_show_options
			$__g_diff_common_options
			"
		return
		;;
	esac
	__g_complete_revlist_file
}

_g_show_branch ()
{
	case "$cur" in
	--*)
		__gcomp_builtin show-branch
		return
		;;
	esac
	__g_complete_revlist
}

__gcomp_directories ()
{
	local _tmp_dir _tmp_completions _found=0

	# Get the directory of the current token; this differs from dirname
	# in that it keeps up to the final trailing slash.  If no slash found
	# that's fine too.
	[[ "$cur" =~ .*/ ]]
	_tmp_dir=$BASH_REMATCH

	# Find possible directory completions, adding trailing '/' characters,
	# de-quoting, and handling unusual characters.
	while IFS= read -r -d $'\0' c ; do
		# If there are directory completions, find ones that start
		# with "$cur", the current token, and put those in COMPREPLY
		if [[ $c == "$cur"* ]]; then
			COMPREPLY+=("$c/")
			_found=1
		fi
	done < <(__g ls-tree -z -d --name-only HEAD $_tmp_dir)

	if [[ $_found == 0 ]] && [[ "$cur" =~ /$ ]]; then
		# No possible further completions any deeper, so assume we're at
		# a leaf directory and just consider it complete
		__gcomp_direct_append "$cur "
	elif [[ $_found == 0 ]]; then
		# No possible completions found.  Avoid falling back to
		# bash's default file and directory completion, because all
		# valid completions have already been searched and the
		# fallbacks can do nothing but mislead.  In fact, they can
		# mislead in three different ways:
		#    1) Fallback file completion makes no sense when asking
		#       for directory completions, as this function does.
		#    2) Fallback directory completion is bad because
		#       e.g. "/pro" is invalid and should NOT complete to
		#       "/proc".
		#    3) Fallback file/directory completion only completes
		#       on paths that exist in the current working tree,
		#       i.e. which are *already* part of their
		#       sparse-checkout.  Thus, normal file and directory
		#       completion is always useless for "g
		#       sparse-checkout add" and is also problematic for
		#       "g sparse-checkout set" unless using it to
		#       strictly narrow the checkout.
		COMPREPLY=( "" )
	fi
}

# In non-cone mode, the arguments to {set,add} are supposed to be
# patterns, relative to the toplevel directory.  These can be any kind
# of general pattern, like 'subdir/*.c' and we can't complete on all
# of those.  However, if the user presses Tab to get tab completion, we
# presume that they are trying to provide a pattern that names a specific
# path.
__gcomp_slash_leading_paths ()
{
	local dequoted_word pfx="" cur_ toplevel

	# Since we are dealing with a sparse-checkout, subdirectories may not
	# exist in the local working copy.  Therefore, we want to run all
	# ls-files commands relative to the repository toplevel.
	toplevel="$(g rev-parse --show-toplevel)/"

	__g_dequote "$cur"

	# If the paths provided by the user already start with '/', then
	# they are considered relative to the toplevel of the repository
	# already.  If they do not start with /, then we need to adjust
	# them to start with the appropriate prefix.
	case "$cur" in
	/*)
		cur="${cur:1}"
		;;
	*)
		pfx="$(__g rev-parse --show-prefix)"
	esac

	# Since sparse-index is limited to cone-mode, in non-cone-mode the
	# list of valid paths is precisely the cached files in the index.
	#
	# NEEDSWORK:
	#   1) We probably need to take care of cases where ls-files
	#      responds with special quoting.
	#   2) We probably need to take care of cases where ${cur} has
	#      some kind of special quoting.
	#   3) On top of any quoting from 1 & 2, we have to provide an extra
	#      level of quoting for any paths that contain a '*', '?', '\',
	#      '[', ']', or leading '#' or '!' since those will be
	#      interpreted by sparse-checkout as something other than a
	#      literal path character.
	# Since there are two types of quoting here, this might get really
	# complex.  For now, just punt on all of this...
	completions="$(__g -C "${toplevel}" -c core.quotePath=false \
			 ls-files --cached -- "${pfx}${cur}*" \
			 | sed -e s%^%/% -e 's%$% %')"
	# Note, above, though that we needed all of the completions to be
	# prefixed with a '/', and we want to add a space so that bash
	# completion will actually complete an entry and let us move on to
	# the next one.

	# Return what we've found.
	if test -n "$completions"; then
		# We found some completions; return them
		local IFS=$'\n'
		COMPREPLY=($completions)
	else
		# Do NOT fall back to bash-style all-local-files-and-dirs
		# when we find no match.  Such options are worse than
		# useless:
		#     1. "g sparse-checkout add" needs paths that are NOT
		#        currently in the working copy.  "g
		#        sparse-checkout set" does as well, except in the
		#        special cases when users are only trying to narrow
		#        their sparse checkout to a subset of what they
		#        already have.
		#
		#     2. A path like '.config' is ambiguous as to whether
		#        the user wants all '.config' files throughout the
		#        tree, or just the one under the current directory.
		#        It would result in a warning from the
		#        sparse-checkout command due to this.  As such, all
		#        completions of paths should be prefixed with a
		#        '/'.
		#
		#     3. We don't want paths prefixed with a '/' to
		#        complete files in the system root directory, we
		#        want it to complete on files relative to the
		#        repository root.
		#
		# As such, make sure that NO completions are offered rather
		# than falling back to bash's default completions.
		COMPREPLY=( "" )
	fi
}

_g_sparse_checkout ()
{
	local subcommands="list init set disable add reapply"
	local subcommand="$(__g_find_on_cmdline "$subcommands")"
	local using_cone=true
	if [ -z "$subcommand" ]; then
		__gcomp "$subcommands"
		return
	fi

	case "$subcommand,$cur" in
	*,--*)
		__gcomp_builtin sparse-checkout_$subcommand "" "--"
		;;
	set,*|add,*)
		if [[ "$(__g config core.sparseCheckout)" == "true" &&
		      "$(__g config core.sparseCheckoutCone)" == "false" &&
		      -z "$(__g_find_on_cmdline --cone)" ]]; then
			using_cone=false
		fi
		if [[ -n "$(__g_find_on_cmdline --no-cone)" ]]; then
			using_cone=false
		fi
		if [[ "$using_cone" == "true" ]]; then
			__gcomp_directories
		else
			 __gcomp_slash_leading_paths
		fi
	esac
}

_g_stash ()
{
	local subcommands='push list show apply clear drop pop create branch'
	local subcommand="$(__g_find_on_cmdline "$subcommands save")"

	if [ -z "$subcommand" ]; then
		case "$((cword - __g_cmd_idx)),$cur" in
		*,--*)
			__gcomp_builtin stash_push
			;;
		1,sa*)
			__gcomp "save"
			;;
		1,*)
			__gcomp "$subcommands"
			;;
		esac
		return
	fi

	case "$subcommand,$cur" in
	list,--*)
		# NEEDSWORK: can we somehow unify this with the options in _g_log() and _g_show()
		__gcomp_builtin stash_list "$__g_log_common_options $__g_diff_common_options"
		;;
	show,--*)
		__gcomp_builtin stash_show "$__g_diff_common_options"
		;;
	*,--*)
		__gcomp_builtin "stash_$subcommand"
		;;
	branch,*)
		if [ $cword -eq $((__g_cmd_idx+2)) ]; then
			__g_complete_refs
		else
			__gcomp_nl "$(__g stash list \
					| sed -n -e 's/:.*//p')"
		fi
		;;
	show,*|apply,*|drop,*|pop,*)
		__gcomp_nl "$(__g stash list \
				| sed -n -e 's/:.*//p')"
		;;
	esac
}

_g_submodule ()
{
	__g_has_doubledash && return

	local subcommands="add status init deinit update set-branch set-url summary foreach sync absorbgdirs"
	local subcommand="$(__g_find_on_cmdline "$subcommands")"
	if [ -z "$subcommand" ]; then
		case "$cur" in
		--*)
			__gcomp "--quiet"
			;;
		*)
			__gcomp "$subcommands"
			;;
		esac
		return
	fi

	case "$subcommand,$cur" in
	add,--*)
		__gcomp "--branch --force --name --reference --depth"
		;;
	status,--*)
		__gcomp "--cached --recursive"
		;;
	deinit,--*)
		__gcomp "--force --all"
		;;
	update,--*)
		__gcomp "
			--init --remote --no-fetch
			--recommend-shallow --no-recommend-shallow
			--force --rebase --merge --reference --depth --recursive --jobs
		"
		;;
	set-branch,--*)
		__gcomp "--default --branch"
		;;
	summary,--*)
		__gcomp "--cached --files --summary-limit"
		;;
	foreach,--*|sync,--*)
		__gcomp "--recursive"
		;;
	*)
		;;
	esac
}

_g_svn ()
{
	local subcommands="
		init fetch clone rebase dcommit log find-rev
		set-tree commit-diff info create-ignore propget
		proplist show-ignore show-externals branch tag blame
		migrate mkdirs reset gc
		"
	local subcommand="$(__g_find_on_cmdline "$subcommands")"
	if [ -z "$subcommand" ]; then
		__gcomp "$subcommands"
	else
		local remote_opts="--username= --config-dir= --no-auth-cache"
		local fc_opts="
			--follow-parent --authors-file= --repack=
			--no-metadata --use-svm-props --use-svnsync-props
			--log-window-size= --no-checkout --quiet
			--repack-flags --use-log-author --localtime
			--add-author-from
			--recursive
			--ignore-paths= --include-paths= $remote_opts
			"
		local init_opts="
			--template= --shared= --trunk= --tags=
			--branches= --stdlayout --minimize-url
			--no-metadata --use-svm-props --use-svnsync-props
			--rewrite-root= --prefix= $remote_opts
			"
		local cmt_opts="
			--edit --rmdir --find-copies-harder --copy-similarity=
			"

		case "$subcommand,$cur" in
		fetch,--*)
			__gcomp "--revision= --fetch-all $fc_opts"
			;;
		clone,--*)
			__gcomp "--revision= $fc_opts $init_opts"
			;;
		init,--*)
			__gcomp "$init_opts"
			;;
		dcommit,--*)
			__gcomp "
				--merge --strategy= --verbose --dry-run
				--fetch-all --no-rebase --commit-url
				--revision --interactive $cmt_opts $fc_opts
				"
			;;
		set-tree,--*)
			__gcomp "--stdin $cmt_opts $fc_opts"
			;;
		create-ignore,--*|propget,--*|proplist,--*|show-ignore,--*|\
		show-externals,--*|mkdirs,--*)
			__gcomp "--revision="
			;;
		log,--*)
			__gcomp "
				--limit= --revision= --verbose --incremental
				--oneline --show-commit --non-recursive
				--authors-file= --color
				"
			;;
		rebase,--*)
			__gcomp "
				--merge --verbose --strategy= --local
				--fetch-all --dry-run $fc_opts
				"
			;;
		commit-diff,--*)
			__gcomp "--message= --file= --revision= $cmt_opts"
			;;
		info,--*)
			__gcomp "--url"
			;;
		branch,--*)
			__gcomp "--dry-run --message --tag"
			;;
		tag,--*)
			__gcomp "--dry-run --message"
			;;
		blame,--*)
			__gcomp "--g-format"
			;;
		migrate,--*)
			__gcomp "
				--config-dir= --ignore-paths= --minimize
				--no-auth-cache --username=
				"
			;;
		reset,--*)
			__gcomp "--revision= --parent"
			;;
		*)
			;;
		esac
	fi
}

_g_symbolic_ref () {
	case "$cur" in
	--*)
		__gcomp_builtin symbolic-ref
		return
		;;
	esac

	__g_complete_refs
}

_g_tag ()
{
	local i c="$__g_cmd_idx" f=0
	while [ $c -lt $cword ]; do
		i="${words[c]}"
		case "$i" in
		-d|--delete|-v|--verify)
			__gcomp_direct "$(__g_tags "" "$cur" " ")"
			return
			;;
		-f)
			f=1
			;;
		esac
		((c++))
	done

	case "$prev" in
	-m|-F)
		;;
	-*|tag)
		if [ $f = 1 ]; then
			__gcomp_direct "$(__g_tags "" "$cur" " ")"
		fi
		;;
	*)
		__g_complete_refs
		;;
	esac

	case "$cur" in
	--*)
		__gcomp_builtin tag
		;;
	esac
}

_g_whatchanged ()
{
	_g_log
}

__g_complete_worktree_paths ()
{
	local IFS=$'\n'
	# Generate completion reply from worktree list skipping the first
	# entry: it's the path of the main worktree, which can't be moved,
	# removed, locked, etc.
	__gcomp_nl "$(__g worktree list --porcelain |
		sed -n -e '2,$ s/^worktree //p')"
}

_g_worktree ()
{
	local subcommands="add list lock move prune remove unlock"
	local subcommand subcommand_idx

	subcommand="$(__g_find_on_cmdline --show-idx "$subcommands")"
	subcommand_idx="${subcommand% *}"
	subcommand="${subcommand#* }"

	case "$subcommand,$cur" in
	,*)
		__gcomp "$subcommands"
		;;
	*,--*)
		__gcomp_builtin worktree_$subcommand
		;;
	add,*)	# usage: g worktree add [<options>] <path> [<commit-ish>]
		# Here we are not completing an --option, it's either the
		# path or a ref.
		case "$prev" in
		-b|-B)	# Complete refs for branch to be created/reset.
			__g_complete_refs
			;;
		-*)	# The previous word is an -o|--option without an
			# unstuck argument: have to complete the path for
			# the new worktree, so don't list anything, but let
			# Bash fall back to filename completion.
			;;
		*)	# The previous word is not an --option, so it must
			# be either the 'add' subcommand, the unstuck
			# argument of an option (e.g. branch for -b|-B), or
			# the path for the new worktree.
			if [ $cword -eq $((subcommand_idx+1)) ]; then
				# Right after the 'add' subcommand: have to
				# complete the path, so fall back to Bash
				# filename completion.
				:
			else
				case "${words[cword-2]}" in
				-b|-B)	# After '-b <branch>': have to
					# complete the path, so fall back
					# to Bash filename completion.
					;;
				*)	# After the path: have to complete
					# the ref to be checked out.
					__g_complete_refs
					;;
				esac
			fi
			;;
		esac
		;;
	lock,*|remove,*|unlock,*)
		__g_complete_worktree_paths
		;;
	move,*)
		if [ $cword -eq $((subcommand_idx+1)) ]; then
			# The first parameter must be an existing working
			# tree to be moved.
			__g_complete_worktree_paths
		else
			# The second parameter is the destination: it could
			# be any path, so don't list anything, but let Bash
			# fall back to filename completion.
			:
		fi
		;;
	esac
}

__g_complete_common () {
	local command="$1"

	case "$cur" in
	--*)
		__gcomp_builtin "$command"
		;;
	esac
}

__g_cmds_with_parseopt_helper=
__g_support_parseopt_helper () {
	test -n "$__g_cmds_with_parseopt_helper" ||
		__g_cmds_with_parseopt_helper="$(__g --list-cmds=parseopt)"

	case " $__g_cmds_with_parseopt_helper " in
	*" $1 "*)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

__g_have_func () {
	declare -f -- "$1" >/dev/null 2>&1
}

__g_complete_command () {
	local command="$1"
	local completion_func="_g_${command//-/_}"
	if ! __g_have_func $completion_func &&
		__g_have_func _completion_loader
	then
		_completion_loader "g-$command"
	fi
	if __g_have_func $completion_func
	then
		$completion_func
		return 0
	elif __g_support_parseopt_helper "$command"
	then
		__g_complete_common "$command"
		return 0
	else
		return 1
	fi
}

__g_main ()
{
	local i c=1 command __g_dir __g_repo_path
	local __g_C_args C_args_count=0
	local __g_cmd_idx

	while [ $c -lt $cword ]; do
		i="${words[c]}"
		case "$i" in
		--g-dir=*)
			__g_dir="${i#--g-dir=}"
			;;
		--g-dir)
			((c++))
			__g_dir="${words[c]}"
			;;
		--bare)
			__g_dir="."
			;;
		--help)
			command="help"
			break
			;;
		-c|--work-tree|--namespace)
			((c++))
			;;
		-C)
			__g_C_args[C_args_count++]=-C
			((c++))
			__g_C_args[C_args_count++]="${words[c]}"
			;;
		-*)
			;;
		*)
			command="$i"
			__g_cmd_idx="$c"
			break
			;;
		esac
		((c++))
	done

	if [ -z "${command-}" ]; then
		case "$prev" in
		--g-dir|-C|--work-tree)
			# these need a path argument, let's fall back to
			# Bash filename completion
			return
			;;
		-c)
			__g_complete_config_variable_name_and_value
			return
			;;
		--namespace)
			# we don't support completing these options' arguments
			return
			;;
		esac
		case "$cur" in
		--*)
			__gcomp "
			--paginate
			--no-pager
			--g-dir=
			--bare
			--version
			--exec-path
			--exec-path=
			--html-path
			--man-path
			--info-path
			--work-tree=
			--namespace=
			--no-replace-objects
			--help
			"
			;;
		*)
			if test -n "${GIT_TESTING_PORCELAIN_COMMAND_LIST-}"
			then
				__gcomp "$GIT_TESTING_PORCELAIN_COMMAND_LIST"
			else
				local list_cmds=list-mainporcelain,others,nohelpers,alias,list-complete,config

				if test "${GIT_COMPLETION_SHOW_ALL_COMMANDS-}" = "1"
				then
					list_cmds=builtins,$list_cmds
				fi
				__gcomp "$(__g --list-cmds=$list_cmds)"
			fi
			;;
		esac
		return
	fi

	__g_complete_command "$command" && return

	local expansion=$(__g_aliased_command "$command")
	if [ -n "$expansion" ]; then
		words[1]=$expansion
		__g_complete_command "$expansion"
	fi
}

__gk_main ()
{
	__g_has_doubledash && return

	local __g_repo_path
	__g_find_repo_path

	local merge=""
	if __g_pseudoref_exists MERGE_HEAD; then
		merge="--merge"
	fi
	case "$cur" in
	--*)
		__gcomp "
			$__g_log_common_options
			$__g_log_gk_options
			$merge
			"
		return
		;;
	esac
	__g_complete_revlist
}

if [[ -n ${ZSH_VERSION-} && -z ${GIT_SOURCING_ZSH_COMPLETION-} ]]; then
	echo "ERROR: this script is obsolete, please see g-completion.zsh" 1>&2
	return
fi

__g_func_wrap ()
{
	local cur words cword prev
	local __g_cmd_idx=0
	_get_comp_words_by_ref -n =: cur words cword prev
	$1
}

___g_complete ()
{
	local wrapper="__g_wrap${2}"
	eval "$wrapper () { __g_func_wrap $2 ; }"
	complete -o bashdefault -o default -o nospace -F $wrapper $1 2>/dev/null \
		|| complete -o default -o nospace -F $wrapper $1
}

# Setup the completion for g commands
# 1: command or alias
# 2: function to call (e.g. `g`, `gk`, `g_fetch`)
__g_complete ()
{
	local func

	if __g_have_func $2; then
		func=$2
	elif __g_have_func __$2_main; then
		func=__$2_main
	elif __g_have_func _$2; then
		func=_$2
	else
		echo "ERROR: could not find function '$2'" 1>&2
		return 1
	fi
	___g_complete $1 $func
}

___g_complete g __g_main
___g_complete gk __gk_main

# The following are necessary only for Cygwin, and only are needed
# when the user has tab-completed the executable name and consequently
# included the '.exe' suffix.
#
if [ "$OSTYPE" = cygwin ]; then
	___g_complete g.exe __g_main
fi
