import ctypes, struct, sys, os
lc = ctypes.CDLL(os.environ.get('LCMS_LIB', 'liblcms2.so.2'))
lc.cmsOpenProfileFromMem.restype = ctypes.c_void_p
lc.cmsOpenProfileFromMem.argtypes = [ctypes.c_char_p, ctypes.c_uint32]
lc.cmsCreateTransform.restype = ctypes.c_void_p
lc.cmsCreateTransform.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32]
lc.cmsDoTransform.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32]
lc.cmsGetColorSpace.restype = ctypes.c_uint32
lc.cmsGetColorSpace.argtypes = [ctypes.c_void_p]
lc.cmsChannelsOf.restype = ctypes.c_uint32
lc.cmsChannelsOf.argtypes = [ctypes.c_uint32]
lc.cmsDeleteTransform.argtypes = [ctypes.c_void_p]
lc.cmsCloseProfile.argtypes = [ctypes.c_void_p]
lc.cmsGetEncodedCMMversion.restype = ctypes.c_int
NOCACHE = 0x0040

def profile(data):
    p = lc.cmsOpenProfileFromMem(data, len(data))
    if not p: raise RuntimeError('bad profile')
    return p

def transform(src_bytes, dst_bytes, intent, points):
    """points: list of float tuples; returns (nin, nout, list of output tuples)"""
    s = profile(src_bytes); d = profile(dst_bytes)
    nin = lc.cmsChannelsOf(lc.cmsGetColorSpace(s)); nout = lc.cmsChannelsOf(lc.cmsGetColorSpace(d))
    fmt = lambda n: (1 << 22) | (n << 3) | 4
    x = lc.cmsCreateTransform(s, fmt(nin), d, fmt(nout), intent, NOCACHE)
    if not x: raise RuntimeError('transform failed')
    n = len(points)
    inbuf = (ctypes.c_float * (n * nin))(*[v for p in points for v in p])
    outbuf = (ctypes.c_float * (n * nout))()
    lc.cmsDoTransform(x, inbuf, outbuf, n)
    out = [tuple(outbuf[i * nout:(i + 1) * nout]) for i in range(n)]
    lc.cmsDeleteTransform(x); lc.cmsCloseProfile(s); lc.cmsCloseProfile(d)
    return nin, nout, out

if __name__ == '__main__':
    print('lcms version', lc.cmsGetEncodedCMMversion())
