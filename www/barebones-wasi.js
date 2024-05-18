var barebonesWasi = function() {
    var moduleInstanceExports = null;

    var WASI_ESUCCESS = 0;
    var WASI_EBADF = 8;
    var WASI_EINVAL = 28;
    var WASI_ENOSYS = 52;

    var WASI_STDOUT_FILENO = 1;

    function setModuleInstance(instance) {
        moduleInstanceExports = instance.exports;
    }

    function getModuleMemoryDataView() {
        // call this any time you'll be reading or writing to a module's memory 
        // the returned DataView tends to be dissaociated with the module's memory buffer at the will of the WebAssembly engine 
        // cache the returned DataView at your own peril!!
        return new DataView(moduleInstanceExports.memory.buffer);
    }

    function path_open(fd, dirflags, path, oflags, fs_rights_base, fs_rights_inheriting, fdflags) {
        return -1;
    }

    function fd_filestat_get(fd, bufPtr) {
        var view = getModuleMemoryDataView();

        view.setUint8(bufPtr, fd);
        view.setUint16(bufPtr + 2, 0, !0);
        view.setUint16(bufPtr + 4, 0, !0);

        function setBigUint64(byteOffset, value, littleEndian) {

            var lowWord = value;
            var highWord = 0;

            view.setUint32(littleEndian ? 0 : 4, lowWord, littleEndian);
            view.setUint32(littleEndian ? 4 : 0, highWord, littleEndian);
        }

        setBigUint64(bufPtr + 8, 0, !0);
        setBigUint64(bufPtr + 8 + 8, 0, !0);

        return WASI_ESUCCESS;
    }

    function fd_seek(fd, offset, whence, newOffsetPtr) {

    }

    function fd_read(fd, iovs) {
        return 0;
    }

    function fd_write(fd, iovs, iovsLen, nwritten) {
        var view = getModuleMemoryDataView();

        var written = 0;
        var bufferBytes = [];

        function getiovs(iovs, iovsLen) {
            // iovs* -> [iov, iov, ...]
            // __wasi_ciovec_t {
            //   void* buf,
            //   size_t buf_len,
            // }
            var buffers = Array.from({
                length: iovsLen
            }, function(_, i) {
                var ptr = iovs + i * 8;
                var buf = view.getUint32(ptr, !0);
                var bufLen = view.getUint32(ptr + 4, !0);

                return new Uint8Array(moduleInstanceExports.memory.buffer, buf, bufLen);
            });

            return buffers;
        }

        var buffers = getiovs(iovs, iovsLen);

        function writev(iov) {
            for (var b = 0; b < iov.byteLength; b++) {
                bufferBytes.push(iov[b]);
            }
            written += b;
        }

        buffers.forEach(writev);

        if (fd === WASI_STDOUT_FILENO) console.log(String.fromCharCode.apply(null, bufferBytes));

        view.setUint32(nwritten, written, !0);

        return WASI_ESUCCESS;
    }

    function fd_close(fd) {
        return WASI_ENOSYS;
    }

    function random_get(buf, buf_len) {

    }

    function proc_exit(rval) {
        return WASI_ENOSYS;
    }

    return {
        setModuleInstance: setModuleInstance,
        path_open: path_open,
        fd_filestat_get: fd_filestat_get,
        fd_seek: fd_seek,
        fd_read: fd_read,
        fd_write: fd_write,
        fd_close: fd_close,
        random_get: random_get,
        proc_exit: proc_exit,
    }
}

export {
    barebonesWasi
}
