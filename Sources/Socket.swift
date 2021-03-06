//
//  Socket.swift
//  Socket.swift
//
//  Created by Orkhan Alikhanov on 7/3/17.
//  Copyright © 2017 BiAtoms. All rights reserved.
//

import Foundation

public typealias FileDescriptor = Int32
public typealias Byte = UInt8
public typealias Port = in_port_t
public typealias SocketAddress = sockaddr
public typealias TimeValue = timeval

open class Socket {
    open let fileDescriptor: FileDescriptor
    
    required public init(with fileDescriptor: FileDescriptor) {
        self.fileDescriptor = fileDescriptor
    }
       
    required public init(_ family: Family, type: Type = .stream, protocol: Protocol = .tcp) throws {
        self.fileDescriptor = try ing{ socket(family.rawValue, type.rawValue, `protocol`.rawValue) }
    }
    
    open func close() {
        //Dont close after an error. see http://man7.org/linux/man-pages/man2/close.2.html#NOTES
        //TODO: Handle error on close
        _ = OS.close(fileDescriptor)
    }
    
    open func read() throws -> Byte {
        var byte: Byte = 0
        try ing { OS.recv(fileDescriptor, &byte, 1, 0) }
        return byte
    }

    open func read(_ buffer: UnsafeMutableRawPointer, bufferSize: Int) throws -> Int {
        let received = try ing { OS.recv(fileDescriptor, buffer, bufferSize, 0) }
        return received
    }

    open func write(_ buffer: UnsafeRawPointer, length: Int) throws {
        var totalWritten = 0
        while totalWritten < length {
            let written = OS.write(fileDescriptor, buffer + totalWritten, length - totalWritten)
            if written <= 0 { //see http://man7.org/linux/man-pages/man2/write.2.html#RETURN_VALUE
                throw Error(errno: errno)
            }
            totalWritten += written
        }
    }
        
    open func set<T>(option: Option<T>, _ value: T) throws {
        // setsockopt expects at least Int32 structure, meaning 4 bytes at least.
        // When the `value` variable is Bool, MemoryLayout<Bool>.size returns 1 and
        // bytes in memory are garbage except one of them. (eg. [0, 241, 49, 19], first indicates false)
        // Passing a pointer to `value` variable and size of Int32 (which is 4) into setsockopt
        // would be equal to always passing true since although the byte sequance [0, 241, 49, 19] of `value`
        // variable is false as Bool, it is non-zero as an Int32.
        // We avoid it by explicitly checking whether T is Bool and passing Int32 0 or 1.
        
        let size = value is Bool ? MemoryLayout<Int32>.size : MemoryLayout<T>.size
        var state: Any = value is Bool ? (value as! Bool == true ? 1 : 0) : value
        
        try ing { setsockopt(fileDescriptor, SOL_SOCKET, option.rawValue, &state, socklen_t(size)) }
    }
    
    open func bind(port: Port, address: String? = nil) throws {
        var addr = SocketAddress(port: port, address: address)
        try ing {  OS.bind(fileDescriptor, &addr, socklen_t(MemoryLayout<SocketAddress>.size)) }
    }
    
    open func connect(port: Port, address: String? = nil) throws {
        var addr = SocketAddress(port: port, address: address)
        try ing {  OS.connect(fileDescriptor, &addr, socklen_t(MemoryLayout<SocketAddress>.size)) }
    }
    
    open func listen(backlog: Int32 = SOMAXCONN) throws {
        try ing { OS.listen(fileDescriptor, backlog) }
    }
    
    open func accept() throws -> Self {
        var addrlen: socklen_t = 0, addr = sockaddr()
        let client = try ing { OS.accept(fileDescriptor, &addr, &addrlen) }
        return type(of: self).init(with: client)
    }
}
extension Socket {
    open class func tcpListening(port: Port, address: String? = nil, maxPendingConnection: Int32 = SOMAXCONN) throws -> Self {
        
        let socket = try self.init(.inet)
        try socket.set(option: .reuseAddress, true)
        try socket.bind(port: port, address: address)
        try socket.listen(backlog: maxPendingConnection)
        
        return socket
    }
}


extension Socket {
    open func write(_ bytes: [Byte]) throws {
        try self.write(bytes, length: bytes.count)
    }
}

extension SocketAddress {
    public init(port: Port, address: String? = nil) {
        var addr = sockaddr_in()
        #if !os(Linux)
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: in_addr_t(0))
        addr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)
        if let address = address, address.withCString({ cstring in inet_pton(AF_INET, cstring, &addr.sin_addr) }) == 1 {
            // print("\(address) is converted to \(addr.sin_addr).")
        } else {
            // print("\(address) is not converted.")
        }
        
        self = withUnsafePointer(to: &addr) {
            UnsafePointer<SocketAddress>(OpaquePointer($0)).pointee
        }
    }
}

extension TimeValue {
    public init(seconds: Int, milliseconds: Int = 0, microseconds: Int = 0) {
        #if !os(Linux)
            let microseconds = Int32(microseconds)
            let milliseconds = Int32(milliseconds)
        #endif
        self.init(tv_sec: seconds, tv_usec: microseconds + milliseconds * 1000)
    }

}
