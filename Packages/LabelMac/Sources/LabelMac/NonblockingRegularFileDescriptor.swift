import Darwin

/// Opens a prospective regular file without allowing special files to block
/// before their descriptor metadata can be validated by the caller.
enum NonblockingRegularFileDescriptor {
    private static let flags = O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC

    static func open(path: String) -> Int32 {
        Darwin.open(path, flags)
    }

    static func open(at directory: Int32, name: String) -> Int32 {
        Darwin.openat(directory, name, flags)
    }
}
