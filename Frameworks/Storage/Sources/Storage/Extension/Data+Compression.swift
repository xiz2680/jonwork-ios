//
//  Data+Compression.swift
//  Storage
//
//  Created by king on 2025/10/17.
//

import Compression
import Foundation

extension Data {
    func compressed(using algorithm: compression_algorithm = COMPRESSION_LZFSE) -> Data? {
        process(algorithm: algorithm, operation: COMPRESSION_STREAM_ENCODE)
    }

    func decompressed(using algorithm: compression_algorithm = COMPRESSION_LZFSE) -> Data? {
        process(algorithm: algorithm, operation: COMPRESSION_STREAM_DECODE)
    }

    private func process(algorithm: compression_algorithm, operation: compression_stream_operation) -> Data? {
        withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcBuffer.baseAddress else { return nil }
            let srcSize = srcBuffer.count

            let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            guard compression_stream_init(streamPointer, operation, algorithm) != COMPRESSION_STATUS_ERROR else {
                return nil
            }

            defer {
                compression_stream_destroy(streamPointer)
                streamPointer.deallocate()
            }

            let dstBufferSize = 64 * 1024
            let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: dstBufferSize)
            defer { dstBuffer.deallocate() }

            var output = Data()
            streamPointer.pointee.src_ptr = srcBase.assumingMemoryBound(to: UInt8.self)
            streamPointer.pointee.src_size = srcSize
            streamPointer.pointee.dst_ptr = dstBuffer
            streamPointer.pointee.dst_size = dstBufferSize

            while true {
                let flags: Int32 = operation == COMPRESSION_STREAM_ENCODE
                    ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                    : 0

                let status = compression_stream_process(streamPointer, flags)
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    output.append(dstBuffer, count: dstBufferSize - streamPointer.pointee.dst_size)
                    if status == COMPRESSION_STATUS_END { return output }
                    streamPointer.pointee.dst_ptr = dstBuffer
                    streamPointer.pointee.dst_size = dstBufferSize
                default:
                    return nil
                }
            }
        }
    }
}
