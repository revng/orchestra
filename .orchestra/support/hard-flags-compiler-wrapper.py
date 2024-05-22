#!/usr/bin/env python3

import os
import sys
import tempfile
import shlex

from itertools import chain
from subprocess import Popen

source_extensions = set([".c", ".cpp", ".cxx", ".cc", ".s", ".S", ".C", ".c++"])
program_name = sys.argv[0]
is_cxx = program_name.endswith("++")
is_clang_tidy = program_name.endswith("clang-tidy")
is_clang = (program_name.endswith("clang")
            or program_name.endswith("clang++"))
this_path = os.path.realpath(__file__)
flags = []

if os.environ.get("HARD_WRAPPER_VERBOSE", "0") == "1":
    def log(message):
        sys.stderr.write(message + "\n")
else:
    def log(message):
        pass

def shlex_join(split_command):
    return ' '.join(shlex.quote(arg) for arg in split_command)

def which(program, exclude):
    def is_exe(fpath):
        return os.path.isfile(fpath) and os.access(fpath, os.X_OK)

    for path in os.environ["PATH"].split(os.pathsep):
        exe_file = os.path.join(path, program)
        if is_exe(exe_file) and os.path.realpath(exe_file) != this_path:
            return exe_file

    log(f"Error: couldn't find {program}")
    sys.exit(1)

def replace_argv0(arguments):
    result = list(arguments)
    return [which(os.path.basename(arguments[0]), this_path)] + arguments[1:]

def run(arguments):
    log(f"Popen({shlex_join(arguments)})")
    returncode = Popen(arguments).wait()
    if returncode != 0:
        sys.exit(returncode)

def exec(arguments):
    run(arguments)
    sys.exit(0)

def is_gold(arguments):
    for argument in reversed(arguments):
        if argument.startswith("-fuse-ld="):
            return argument == "-fuse-ld=gold"
    return False

def get_flags(flags, current_tags, must_have=set(), must_not_have=set()):
    return list(chain(*(arguments
                        for tags, arguments
                        in flags
                        if (tags.issubset(current_tags)
                            and must_have.issubset(tags)
                            and not tags.intersection(must_not_have)))))

def add_arguments_for(original, action):
    is_linking = action == "link"
    old_arguments = []
    arguments = original
    late_tag = set(["late"])

    while arguments != old_arguments:
        old_arguments = arguments
        current_tags = set([action,
                            "cxx" if is_cxx else "c",
                            "clang" if is_clang else "gcc",
                            "gold" if is_gold(arguments) else "bfd"])
        early = get_flags(flags, current_tags, must_not_have=late_tag)
        late = get_flags(flags, current_tags.union(late_tag), must_have=late_tag)
        arguments = [original[0]] + early + original[1:] + late

    return arguments

def clang_tidy(arguments):
    return add_arguments_for(arguments, "clangtidy")

def compile(arguments):
    return add_arguments_for(arguments, "compile")

def link(arguments):
    return add_arguments_for(arguments, "link")

def other(arguments):
    return add_arguments_for(arguments, "other")

def remove_by_indexes(original, indexes):
    result = list(original)
    for index in sorted(indexes, reverse=True):
        del result[index]
    return result

def remove_prefix_argument(args, prefix):
    return [current
            for previous, current
            in zip([None] + args[:-1], args)
            if (not current.startswith(prefix)
                and previous != prefix)]

def replace_output(args, new_output):
    return remove_prefix_argument(args, "-o") + ["-o", new_output]


def starts_with_any(string, prefixes):
    for prefix in prefixes:
        if string.startswith(prefix):
            return True
    return False


def filter_disallowed_paths(arguments, variable, target_argument):
    allowed_prefixes = os.environ.get(variable, "").split(":")

    if not arguments or not allowed_prefixes:
        return arguments

    merged = [arguments[0]]
    for previous_argument, argument in zip(arguments[:-1], arguments[1:]):
        if previous_argument == target_argument:
            merged[-1] += argument
        else:
            merged.append(argument)
    arguments = merged

    return [argument
            for argument
            in arguments
            if (not argument.startswith(target_argument)
                or starts_with_any(os.path.realpath(argument[len(target_argument):]),
                                   allowed_prefixes))]


def main():
    sys.argv = replace_argv0(sys.argv)

    disable_wrapper = int(os.environ.get("HARD_FLAGS_IGNORE", "0")) != 0
    if disable_wrapper:
        exec(other(sys.argv))

    sys.argv = filter_disallowed_paths(sys.argv, "HARD_ALLOWED_INCLUDE_PATH", "-I")
    sys.argv = filter_disallowed_paths(sys.argv, "HARD_ALLOWED_INCLUDE_PATH", "-isystem")
    sys.argv = filter_disallowed_paths(sys.argv, "HARD_ALLOWED_LIBRARY_PATH", "-L")

    prefix = "HARD_FLAGS_"
    for name, value in os.environ.items():
        if name.startswith(prefix):
            flags.append((set(tag.lower()
                              for tag
                              in name[len(prefix):].split("_")),
                          shlex.split(value)))

    # Detect argument indexes representing source files
    has_inputs = False
    source_arguments = set()
    ignore_next = False
    to_ignore = set(["-o", "-L", "-I", "--sysroot", "-idirafter", "-MT", "-MF", "-x"])
    for index, arg in enumerate(sys.argv[1:]):
        if arg in to_ignore:
            ignore_next = True
            continue

        if not ignore_next and not arg.startswith("-"):
            if os.path.extsep in arg:
                _, extension = os.path.splitext(arg)
                if extension in source_extensions:
                    source_arguments.add(index + 1)

                has_inputs = True

            if not os.path.exists(arg):
                log(f"Warning: argument {arg} seems to be a non-existing source file")

        ignore_next = False


    # We are compiling if we have at least a source argument
    is_compiling = bool(source_arguments)

    # Are we linking or compiling an individual translation unit?
    is_linking = (has_inputs
                  and ("-c" not in sys.argv
                       and "-r" not in sys.argv
                       and "-S" not in sys.argv
                       and "-E" not in sys.argv))

    if is_clang_tidy:
        exec(clang_tidy(sys.argv))
    elif is_compiling and is_linking:
        # We need to compile each individual source file first, then link
        with tempfile.TemporaryDirectory() as output_directory:
            for source_argument in source_arguments:
                argument = sys.argv[source_argument]

                # Remove all source_arguments except for the current one
                to_remove = source_arguments - set([source_argument])
                arguments = remove_by_indexes(sys.argv, to_remove)

                # Create a temporary file and set it as output
                prefix = os.path.basename(argument)
                _, output = tempfile.mkstemp(prefix=prefix + ".",
                                             suffix=".o",
                                             dir=output_directory)
                arguments = replace_output(arguments, output)

                # Compile
                run(compile(arguments + ["-c"]))

                # Prepare linker invocation
                sys.argv[source_argument] = output

            # Remove -x
            sys.argv = remove_prefix_argument(sys.argv, "-x")

            # Link
            exec(link(sys.argv))

    elif is_compiling:
        exec(compile(sys.argv))
    elif is_linking:
        exec(link(sys.argv))
    else:
        exec(other(sys.argv))

    return 0

if __name__ == "__main__":
    sys.exit(main())
