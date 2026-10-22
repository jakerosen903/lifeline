import Foundation

/// Command-line entry point. Commands arrive in later tasks.
let usage = """
usage: lifeline <command> [options]
"""
FileHandle.standardError.write(Data(usage.utf8))
exit(2)
