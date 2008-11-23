"""tstools.pyx -- Pyrex bindings for the TS tools

This is being developed on a Mac, running OS X, and also tested on my Ubuntu
system at work.

I do not expect it to build (as it stands) on Windows, as it is making
assumptions that may not follow thereon.

It is my intent to worry about Windows after it works on the platforms that
I can test most easily!
"""

# ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# The Original Code is the MPEG TS, PS and ES tools.
#
# The Initial Developer of the Original Code is Amino Communications Ltd.
# Portions created by the Initial Developer are Copyright (C) 2008
# the Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Tibs (tibs@berlios.de)
#
# ***** END LICENSE BLOCK *****

import array

# If we're going to use definitions like this in more than one pyx file, we'll
# need to define the shared types in a .pxd file and use cimport to import
# them.

cdef extern from "stdio.h":
    ctypedef struct FILE:
        int _fileno
    cdef enum:
        EOF = -1
    cdef FILE *stdout
    # Associate a stream (returned) with an existing file descriptor.
    # The specified mode must be compatible with the existing mode of
    # the file descriptor. Closing the stream will close the descriptor
    # as well.
    cdef FILE *fdopen(int fildes, char *mode)

    cdef FILE *fopen(char *path, char *mode)
    cdef int fclose(FILE *stream)
    cdef int fileno(FILE *stream)

cdef extern from "errno.h":
    cdef int errno

cdef extern from "string.h":
    cdef char *strerror(int errnum)

# Copied from the Pyrex documentation...
cdef extern from "Python.h":
    # Return a new string object with a copy of the string v as value and
    # length len on success, and NULL on failure. If v is NULL, the contents of
    # the string are uninitialized.
    object PyString_FromStringAndSize(char *v, int len)

    # Return a NUL-terminated representation of the contents of the object obj
    # through the output variables buffer and length. 
    #
    # The function accepts both string and Unicode objects as input. For
    # Unicode objects it returns the default encoded version of the object. If
    # length is NULL, the resulting buffer may not contain NUL characters; if
    # it does, the function returns -1 and a TypeError is raised. 
    #
    # The buffer refers to an internal string buffer of obj, not a copy. The
    # data must not be modified in any way, unless the string was just created
    # using PyString_FromStringAndSize(NULL, size). It must not be deallocated.
    # If string is a Unicode object, this function computes the default
    # encoding of string and operates on that. If string is not a string object
    # at all, PyString_AsStringAndSize() returns -1 and raises TypeError.
    int PyString_AsStringAndSize(object obj, char **buffer, Py_ssize_t* length) except -1

    # Returns a pointer to a read-only memory location containing arbitrary
    # data. The obj argument must support the single-segment readable buffer
    # interface. On success, returns 0, sets buffer to the memory location and
    # buffer_len to the buffer length. Returns -1 and sets a TypeError on
    # error.
    int PyObject_AsReadBuffer(object obj, void **buffer, Py_ssize_t *buffer_len) except -1
    # Unfortunately, that second argument is declared "const void **", which
    # seems to mean ending up with grumbles from gcc when we can't declare a
    # const void ** item...

cdef FILE *convert_python_file(object file):
    """Given a Python file object, return an equivalent stream.
    There are *so many things* dodgy about doing this...
    """
    cdef int fileno
    cdef char *mode
    cdef FILE *stream
    fileno = file.fileno()
    mode = file.mode
    stream = fdopen(fileno, mode) 
    if stream == NULL:
        raise TSToolsException, 'Error converting Python file to C FILE *'
    else:
        return stream

cdef extern from "stdint.h":
    ctypedef unsigned char      uint8_t
    ctypedef unsigned           uint16_t
    ctypedef unsigned long      uint32_t
    ctypedef unsigned long long uint64_t
    ctypedef   signed char      int8_t
    ctypedef          int       int16_t
    ctypedef          long      int32_t
    ctypedef          long long int64_t

# PIDs are too long for 16 bits, short enough to fit in 32
ctypedef uint32_t   PID

cdef extern from "compat.h":
    # We don't need to define 'offset_t' exactly, just to let Pyrex
    # know it's vaguely int-like
    ctypedef int offset_t
    ctypedef uint8_t byte  # but we already had our stdint byte daatype

cdef extern from 'es_defns.h':
    # The reader for an ES file
    struct elementary_stream:
        pass

    ctypedef elementary_stream  ES
    ctypedef elementary_stream *ES_p

    # A location within said stream
    struct _ES_offset:
        offset_t    infile      # as used by lseek
        int         inpacket    # in PES file, offset within PES packet

    ctypedef _ES_offset ES_offset

    # An actual ES unit
    struct ES_unit:
        ES_offset   start_posn
        byte       *data
        unsigned    data_len
        unsigned    data_size
        byte        start_code
        byte        PES_had_PTS

    ctypedef ES_unit *ES_unit_p

cdef extern from 'es_fns.h':
    int open_elementary_stream(char *filename, ES_p *es)
    void close_elementary_stream(ES_p *es)

    int build_elementary_stream_file(int input, ES_p *es)
    void free_elementary_stream(ES_p *es)

    int find_and_build_next_ES_unit(ES_p es, ES_unit_p *unit)
    void free_ES_unit(ES_unit_p *unit)
    void report_ES_unit(FILE *stream, ES_unit_p unit)

    # We perhaps need a Python object to represent an ES_offset?
    # Otherwise, it's going to be hard to use them within Python itself
    int seek_ES(ES_p es, ES_offset where)
    int compare_ES_offsets(ES_offset offset1, ES_offset offset2)

    # I'd like to be able to *write* ES files, so...
    # Python file objects can return a file descriptor (i.e., integer)
    # via their fileno() method, so the simplest thing to do may be to
    # add a new C function that uses write() instead of fwrite(). Or I
    # could use fdopen to turn the fileno() into a FILE *...
    int build_ES_unit_from_data(ES_unit_p *unit, byte *data, unsigned data_len)
    int write_ES_unit(FILE *output, ES_unit_p unit)


# Is this the best thing to do?
class TSToolsException(Exception):
    pass

cdef class ESOffset:
    """An offset within an ES file.

    If the ES unit was read directly from a raw ES file, then a simple file
    offset is sufficient.

    However, if we're reading from a PS or TS file (via the PES reading layer),
    then we have the offset of the PES packet, and then the offset of the ES
    unit therein.
    
    We *could* just use a tuple for this, but it's nice to have a bit more
    documentation self-evident.
    """

    # Keep the original names, even though they're not very Pythonic
    cdef readonly long long infile      # Hoping this is 64 bit...
    cdef readonly int       inpacket

    def __cinit__(self, infile=0, inpacket=0):
        self.infile = infile
        self.inpacket = inpacket

    def __init__(self, infile=0, inpacket=0):
        pass

    def __str__(self):
        """Return a fairly compact and (relatively) self-explanatory format
        """
        return '%d+%d'%(self.infile,self.inpacket)

    def __repr__(self):
        """Return something we could be recreated from.
        """
        return 'ESOffset(infile=%d,inpacket=%d)'%(self.infile,self.inpacket)

    def formatted(self):
        """Return a representation that is similar to that returned by the C tools.

        Beware that this is <inpacket>+<infile>, which is reversed from the ``repr``.
        """
        return '%08d/%08d'%(self.inpacket,self.infile)

    def report(self):
        print 'Offset %d in packet at offset %d in file'%(self.inpacket,self.infile)

    def __cmp__(self,other):
        if self.infile > other.infile:
            return 1
        elif self.infile < other.infile:
            return -1
        elif self.inpacket > other.inpacket:
            return 1
        elif self.inpacket < other.inpacket:
            return -1
        else:
            return 0

cdef same_ES_unit(ES_unit_p this, ES_unit_p that):
    """Two ES units do not need to be at the same place to be the same.
    """
    if this.data_len != that.data_len:
        return False
    for 0 <= ii < this.data_len:
        if this.data[ii] != that.data[ii]:
            return False
    return True

cdef class ESUnit       # Forward declaration
cdef object compare_ESUnits(ESUnit this, ESUnit that, int op):
    """op is 2 for ==, 3 for !=, other values not allowed.
    """
    if op == 2:     # ==
        return same_ES_unit(this.unit, that.unit)
    elif op == 3:   # !=
        return not same_ES_unit(this.unit, that.unit)
    else:
        #return NotImplemented
        raise TypeError, 'ESUnit only supports == and != comparisons'

cdef class ESUnit:
    """A Python class representing an ES unit.
    """

    # XXX Or would I be better of with an array.array (or, eventually, bytearray)?
    cdef ES_unit_p unit

    # It appears to be recommended to make __cinit__ expand to take more
    # arguments (if __init__ ever gains them), since both get the same
    # things passed to them. Hmm, normally I'd trust myself, but let's
    # try the recommended route
    def __cinit__(self, data=None, *args,**kwargs):
        cdef char       *buffer
        cdef Py_ssize_t  length
        if data:
            PyString_AsStringAndSize(data, &buffer, &length)
            retval = build_ES_unit_from_data(&self.unit, <byte *>buffer, length);
            if retval < 0:
                raise TSToolsException,'Error building ES unit from Python string'

    def __init__(self,data=None):
        pass

    def report(self):
        """Report (briefly) on an ES unit. This write to C stdout, which means
        that Python has no control over the output. A proper Python version of
        this will be provided eventually.
        """
        report_ES_unit(stdout, self.unit)

    def __dealloc__(self):
        free_ES_unit(&self.unit)

    def __str__(self):
        text = 'ES unit: start code %02x, len %4d:'%(self.unit.start_code,
                                                    self.unit.data_len)
        for 0 <= ii < min(self.unit.data_len,8):
            text += ' %02x'%self.unit.data[ii]

        if self.unit.data_len == 9:
            text += ' %02x'%self.unit.data[8]
        elif self.unit.data_len > 9:
            text += '...'
        return text

    def __repr__(self):
        words = []
        for 0 <= ii < self.unit.data_len:
            words.append('\\x%02x'%self.unit.data[ii])
        return 'ESUnit("%s")'%(''.join(words))

    cdef __set_es_unit(self, ES_unit_p unit):
        if self.unit == NULL:
            raise ValueError,'ES unit already defined'
        else:
            self.unit = unit

    def __richcmp__(self,other,op):
        return compare_ESUnits(self,other,op)

    def __getattr__(self,name):
        if name == 'start_posn':
            return ESOffset(self.unit.start_posn.infile,
                            self.unit.start_posn.inpacket)
        elif name == 'data':
            # Cast the first parameter so that the C compiler is happy
            # when compiling the (derived) tstools.c
            return PyString_FromStringAndSize(<char *>self.unit.data, self.unit.data_len)
        elif name == 'start_code':
            return self.unit.start_code
        elif name == 'PES_had_PTS':
            return self.unit.PES_had_PTS
        else:
            raise AttributeError

cdef class ESFile:
    """A Python class representing an ES stream.

    We support opening for read, or opening (creating) a new file
    for write. For the moment, we don't support appending, and
    support for trying to read and write the same file is undefined.

    So, create a new ESFile as either:

        * ESFile(filename,'r') or
        * ESFile(filename,'w')

    Note that there is always an implicit 'b' attached to the mode (i.e., the
    file is accessed in binary mode).
    """

    cdef FILE *file_stream      # The corresponding C file stream
    cdef int   fileno           # and file number
    cdef ES_p  stream           # For reading an existing ES stream
    cdef readonly object name
    cdef readonly object mode

    # It appears to be recommended to make __cinit__ expand to take more
    # arguments (if __init__ ever gains them), since both get the same
    # things passed to them. Hmm, normally I'd trust myself, but let's
    # try the recommended route
    def __cinit__(self,filename,mode='r',*args,**kwargs):
        actual_mode = mode+'b'
        self.file_stream = fopen(filename,mode)
        if self.file_stream == NULL:
            raise TSToolsException,"Error opening file '%s'"\
                    " with (actual) mode '%s': %s"%(filename,mode,strerror(errno))
        self.fileno = fileno(self.file_stream)
        if mode == 'r':
            retval = build_elementary_stream_file(self.fileno,&self.stream)
            if retval != 0:
                raise TSToolsException,'Error attaching elementary stream to file %s'%filename

    def __init__(self,filename,mode='r'):
        # What should go in __init__ and what in __cinit__ ???
        self.name = filename
        self.mode = mode

    def __dealloc__(self):
        if self.file_stream != NULL:
            retval = fclose(self.file_stream)
            if retval != 0:
                raise TSToolsException,"Error closing file '%s':"\
                        " %s"%(self.name,strerror(errno))
        if self.stream != NULL:
            free_elementary_stream(&self.stream)

    def __iter__(self):
        return self

    def __repr__(self):
        if self.name:
            if self.is_readable:
                return "<ESFile '%s' open for read>"%self.name
            else:
                return "<ESFile '%s' open for write>"%self.name
        else:
            return "<ESFile, closed>"

    def is_readable(self):
        """This is a convenience method, whilst reading and writing are exclusive.
        """
        return self.mode == 'r' and self.stream != NULL

    def is_writable(self):
        """This is a convenience method, whilst reading and writing are exclusive.
        """
        return self.mode == 'w' and self.file_stream != NULL

    cdef _next_ESUnit(self):
        cdef ES_unit_p unit
        # The C function assumes it has a valid ES stream passed to it
        # = I don't think we're always called with such
        if self.stream == NULL:
            raise TSToolsException,'No ES stream to read'

        retval = find_and_build_next_ES_unit(self.stream, &unit)
        if retval == EOF:
            raise StopIteration
        elif retval != 0:
            raise TSToolsException,'Error getting next ES unit from file %s'%self.name

        # From http://www.philhassey.com/blog/2007/12/05/pyrex-from-confusion-to-enlightenment/
        # Pyrex doesn't do type inference, so it doesn't detect that 'u' is allowed
        # to hold an ES_unit_p. It's up to us to *tell* it, specifically, what type
        # 'u' is going to be.
        cdef ESUnit u
        u = ESUnit()
        u.unit = unit
        return u

    # For Pyrex classes, we define a __next__ instead of a next method
    # in order to form our iterator
    def __next__(self):
        """Our iterator interface retrieves the ES units from the stream.
        """
        return self._next_ESUnit()

    def seek(self,*args):
        """Seek to the given 'offset', which should be the start of an ES unit.

        'offset' may be a single integer (if the file is a raw ES file), an
        ESOffset (for any sort of ES file), or a tuple of (infile,inpacket)

        Returns an ESOffset according to where it sought to.
        """
        cdef ES_offset where
        try:
            if len(args) == 1:
                try:
                    where.infile = args[0].infile
                    where.inpacket = args[0].inpacket
                except:
                    where.infile = args[0]
                    where.inpacket = 0
            elif len(args) == 2:
                where.infile, where.inpacket = args
            else:
                raise TypeError
        except:
            raise TypeError,'Seek argument must be one integer, two integers or an ESOffset'
        retval = seek_ES(self.stream,where)
        if retval != 0:
            raise TSToolsException,"Error seeking to %s in file '%s'"%(args,self.name)
        else:
            return ESOffset(where.infile,where.inpacket)

    def read(self):
        """Read the next ES unit from this stream.
        """
        try:
            return self._next_ESUnit()
        except StopIteration:
            raise EOFError

    def write(self, ESUnit unit):
        """Write an ES unit to this stream.
        """
        if self.file_stream == NULL:
            raise TSToolsException,'ESFile does not seem to have been opened for write'

        retval = write_ES_unit(self.file_stream,unit.unit)
        if retval != 0:
            raise TSToolsException,'Error writing ES unit to file %s'%self.name

    def close(self):
        # Apparently we can't call the __dealloc__ method itself,
        # but I think this is sensible to do here...
        if self.file_stream != NULL:
            retval = fclose(self.file_stream)
            if retval != 0:
                raise TSToolsException,"Error closing file '%s':"\
                        " %s"%(filename,strerror(errno))
        if self.stream != NULL:
            free_elementary_stream(&self.stream)
        # And obviously we're not available any more
        self.file_stream = NULL
        self.fileno = -1
        self.name = None
        self.mode = None

    def __enter__(self):
        return self

    def __exit__(self, etype, value, tb):
        if tb is None:
            # No exception, so just finish normally
            self.close()
        else:
            # Exception occurred, so tidy up
            self.close()
            # And allow the exception to be re-raised
            return False

cdef extern from "ts_defns.h":
    struct _ts_reader:
        pass
    ctypedef _ts_reader      TS_reader
    ctypedef _ts_reader     *TS_reader_p

cdef extern from "pidint_defns.h":
    struct _pidint_list:
        int      *number
        uint32_t *pid
        int       length
        int       size
    ctypedef _pidint_list    pidint_list
    ctypedef _pidint_list   *pidint_list_p
    struct _pmt_stream:
        byte         stream_type
        uint32_t     elementary_PID
        uint16_t     ES_info_length
        byte        *ES_info
    ctypedef _pmt_stream    pmt_stream
    ctypedef _pmt_stream   *pmt_stream_p
    struct _pmt:
        uint16_t     program_number
        byte         version_number
        uint32_t     PCR_pid
        uint16_t     program_info_length
        byte        *program_info
        int          streams_size
        int          num_streams
        pmt_stream_p streams
    ctypedef _pmt    pmt
    ctypedef _pmt   *pmt_p

cdef extern from "pidint_fns.h":
    void free_pidint_list(pidint_list_p  *list)
    void free_pmt(pmt_p  *pmt)

    void report_pidint_list(pidint_list_p  list,
                            char          *list_name,
                            char          *int_name,
                            int            pid_first)

class PAT(object):
    """A Program Association Table.

    Always has PID 0x0000.

    Data is:

        * <to be defined>
        * dictionary of {program_number : pid}

    where the 'pid' is the relevant PMT pid.
    """

    def __init__(self, data=None):
        """Initialise the PAT, optionally with its dictionary.
        """
        self._data = {}
        if data:
            # Let our own setattr method check the items make sense
            for key,value in data.items():
                self[key] = value

    def __getitem__(self,key):
        return self._data[key]

    def __setitem__(self,key,value):
        if not (0 <= key <= 0xFFFF):
            raise ValueError,"Program number must be 0..65535, not %d"%key
        if not (0 <= value <= 0x1FFF):
            raise ValueError,"PID must be 0..0x1fff, not %#04x"%value
        self._data[key] = value

    def __delitem__(self,key):
        del self._data[key]

    def __len__(self):
        return len(self._data)

    def __contains__(self,key):
        return key in self._data

    def __eq__(self,other):
        return self._data == other._data

    def __iter__(self):
        return self._data.iteritems()

    def __repr__(self):
        """It is nicer if we make sure the dictionary appears in some sort of
        order.
        """
        words = []
        keys = self._data.keys()
        keys.sort()
        for key in keys:
            words.append('%d:%#x'%(key,self._data[key]))
        return 'PAT({%s})'%(','.join(words))

class PMT(object):
    """A Program Map Table.

    Data is:

        * program_number, version_number, PCR_pid
        * program_info (bytes, as a "string")
        * a dictionary of the streams in this program, as:

            * key:   elementary_PID
            * value: (stream_type, ES_info) 
    """
    pass

cdef extern from "ts_fns.h":
    int open_file_for_TS_read(char *filename, TS_reader_p *tsreader)
    int close_TS_reader(TS_reader_p *tsreader)
    int seek_using_TS_reader(TS_reader_p tsreader, offset_t posn)
    int read_next_TS_packet(TS_reader_p tsreader, byte **packet)
    int split_TS_packet(byte *buf, PID *pid, int *payload_unit_start_indicator,
                        byte **adapt, int *adapt_len,
                        byte **payload, int *payload_len)
    void get_PCR_from_adaptation_field(byte *adapt, int adapt_len, int*got_pcr,
                                       uint64_t *pcr)
    int find_pat(TS_reader_p tsreader, int max, int verbose, int quiet,
                 int *num_read, pidint_list_p *prog_list)
    int find_next_pmt(TS_reader_p tsreader, uint32_t pmt_pid,
                      int max, int verbose, int quiet,
                      int *num_read, pmt_p *pmt)
    int find_pmt(TS_reader_p tsreader, int max, int verbose, int quiet,
                 int *num_read, pmt_p *pmt)
    int extract_prog_list_from_pat(int verbose, byte *data, int data_len,
                                   pidint_list_p *prog_list)


DEF TS_PACKET_LEN = 188

cdef class TSPacket:
    """A convenient representation of a (dissected) TS packet.
    """

    cdef readonly object    data
    cdef readonly PID       pid

    # The following are lazily calculated if necessary
    cdef  byte      _already_split
    cdef  int       _pusi       # payload unit start indicator
    cdef  object    _adapt
    cdef  object    _payload

    # Ditto with looking for a PCR
    cdef  int       _checked_for_pcr
    cdef  object    _pcr        # if we have one

    def __cinit__(self,buffer,*args,**kwargs):
        """The buffer *must* be 188 bytes long, by definition.
        """
        # An array is easier to access than a string, can can be initialised
        # from any sensible sequence. This may not be the most efficient thing
        # to do, though, so later on we might want to consider ways of iterating
        # over TS entries in a file without needing to create TS packets...
        self.data = array.array('B',buffer)
        # We *really* believe that the first character had better be 0x47...
        if self.data[0] != 0x47:
            raise TSToolsException,\
                    'First byte of TS packet is %#02x, not 0x47'%(ord(buffer[0]))
        # And the length is, well, defined
        if len(self.data) != TS_PACKET_LEN:
            raise TSToolsException,\
                    'TS packet is %d bytes long, not %d'%(len(self.data)) 
        # The PID is useful to know early on, and fairly easy to work out
        self.pid = ((ord(buffer[1]) & 0x1F) << 8) | ord(buffer[2])

    def __init__(self,pid=None,pusi=None,adapt=None,payload=None,data=None):
        pass

    def __dealloc__(self):
        pass

    def is_padding(self):
        return self.pid == 0x1fff

    def __str__(self):
        self._split()
        text = 'TS packet PID %04x '%self.pid
        if self.pusi:
            text += '[pusi] '
        if self.adapt and self.payload:
            text += 'A+P '
        elif self.adapt:
            text += 'A '
        elif self.payload:
            text += 'P '
        data = self.data[3:11]
        words = []
        for val in data:
            words.append('%02x'%val)
        text += ' '.join(words) + '...'
        return text

    def __repr__(self):
        words = []
        for val in self.data:
            words.append('\\x%02x'%val)
        return 'TSPacket("%s")'%(''.join(words))

    def __richcmp__(self,other,op):
        if op == 2:     # ==
            return self.data == other.data
        elif op == 3:   # !=
            return self.data != other.data
        else:
            #return NotImplemented
            raise TypeError, 'TSPacket only supports == and != comparisons'

    def _split(self):
        """Split the packet up when requested to do so.
        """
        cdef void       *buffer
        cdef Py_ssize_t  length
        cdef PID         pid
        cdef char       *adapt_buf
        cdef int         adapt_len
        cdef char       *payload_buf
        cdef int         payload_len
        PyObject_AsReadBuffer(self.data, &buffer, &length)
        retval = split_TS_packet(<byte *>buffer,&pid,&self._pusi,
                                 <byte **>&adapt_buf,&adapt_len,
                                 <byte **>&payload_buf,&payload_len)
        if retval < 0:
            raise TSToolsException,'Error splitting TS packet data'
        if adapt_len == 0:
            self._adapt = None
        else:
            self._adapt = PyString_FromStringAndSize(adapt_buf,adapt_len)
        if payload_len == 0:
            self._payload = None
        else:
            self._payload = PyString_FromStringAndSize(payload_buf,payload_len)
        self._already_split = True

    def _determine_PCR(self):
        """Determine our PCR, if we have one.
        Assumes that self._split() has been called already.
        """
        cdef void       *adapt_buf
        cdef Py_ssize_t  adapt_len
        cdef int         got_pcr
        cdef uint64_t    pcr
        if self._adapt:
            PyObject_AsReadBuffer(self._adapt, &adapt_buf, &adapt_len)
            get_PCR_from_adaptation_field(<byte *>adapt_buf, adapt_len,
                                          &got_pcr, &pcr)
        else:
            got_pcr = 0
        self._checked_for_pcr = True    # regardless
        if got_pcr:
            self._pcr = pcr

    def __getattr__(self,name):
        if not self._already_split:
            self._split()
        if name == 'pusi':
            return self._pusi
        elif name == 'adapt':
            return self._adapt
        elif name == 'payload':
            return self._payload
        elif name == "PCR":
            if not self._checked_for_pcr:
                self._determine_PCR()
            return self._pcr
        else:
            raise AttributeError

cdef class TSFile:
    """A Python class representing a TS file.

    We support opening for read, or opening (creating) a new file
    for write. For the moment, we don't support appending, and
    support for trying to read and write the same file is undefined.

    So, create a new TSFile as either:

        * TSFile(filename,'r') or
        * TSFile(filename,'w')

    Note that there is always an implicit 'b' attached to the mode (i.e., the
    file is accessed in binary mode).
    """

    cdef TS_reader_p    tsreader

    cdef readonly object name
    cdef readonly object mode

    cdef readonly object PAT    # The latest PAT read, if any

    # It appears to be recommended to make __cinit__ expand to take more
    # arguments (if __init__ ever gains them), since both get the same
    # things passed to them. Hmm, normally I'd trust myself, but let's
    # try the recommended route
    def __cinit__(self,filename,mode='r',*args,**kwargs):
        actual_mode = mode+'b'
        if mode == 'r':
            retval = open_file_for_TS_read(filename,&self.tsreader)
            if retval == 1:
                raise TSToolsException,"Error opening file '%s'"\
                        " for TS reading: %s"%(filename,strerror(errno))
        elif mode == 'w':
            raise NotImplemented
        else:
            raise TSToolsException,"Error opening file '%s'"\
                    " with mode '%s' (only 'r' and 'w' supported)"%(filename,mode)

    def __init__(self,filename,mode='r'):
        # What should go in __init__ and what in __cinit__ ???
        self.name = filename
        self.mode = mode

    # (__dealloc__ is apparently not allowed to call Python methods,
    # and Python methods don't seem to be allowed to call __dealloc__,
    # so let's have an intermediary)
    cdef _close_for_read(self):
        if self.tsreader != NULL:
            retval = close_TS_reader(&self.tsreader)
            if retval != 0:
                raise TSToolsException,"Error closing file '%s':"\
                        " %s"%(self.name,strerror(errno))

    def __dealloc__(self):
        self._close_for_read()
        #if self.tsreader != NULL:
        #    retval = close_TS_reader(&self.tsreader)
        #    if retval != 0:
        #        raise TSToolsException,"Error closing file '%s':"\
        #                " %s"%(self.name,strerror(errno))

    def __iter__(self):
        return self

    def __repr__(self):
        if self.name:
            if self.is_readable:
                return "<TSFile '%s' open for read>"%self.name
            else:
                return "<TSFile '%s' open for write>"%self.name
        else:
            return "<TSFile, closed>"

    def is_readable(self):
        """This is a convenience method, whilst reading and writing are exclusive.
        """
        return self.mode == 'r' and self.tsreader != NULL
        pass

    def is_writable(self):
        """This is a convenience method, whilst reading and writing are exclusive.
        """
        return self.mode == 'w'
        #return self.mode == 'w' and self.file_stream != NULL
        pass

    cdef TSPacket _next_TSPacket(self):
        """Read the next TS packet and return an equivalent TSPacket instance.

        ``filename`` is given for use in exception messages - it should be the
        name of the file we're reading from (using ``tsreader``). Perhaps the
        tstools C mechanisms should be enhanced to allow that to be recovered
        *from* ``tsreader``.
        """
        # XXX Should we update self.PAT if the packet has PID 0?
        # XXX See tsreport.c::report_ts for how to do this
        cdef byte *buffer
        if self.tsreader == NULL:
            raise TSToolsException,'No TS stream to read'
        retval = read_next_TS_packet(self.tsreader, &buffer)
        if retval == EOF:
            raise StopIteration
        elif retval == 1:
            raise TSToolsException,'Error getting next TS packet from file %s'%self.name
        # Remember the buffer we get handed a pointer to is transient
        # so we need to take a copy of it (which we might as well keep in
        # a Python object...)
        buffer_str = PyString_FromStringAndSize(<char *>buffer, TS_PACKET_LEN)
        try:
            return TSPacket(buffer_str)
        except TSToolsException, what:
            raise TSToolsException,\
                    'Error getting next TS packet from file %s (%s)'%(self.name,what)

    # For Pyrex classes, we define a __next__ instead of a next method
    # in order to form our iterator
    def __next__(self):
        """Our iterator interface retrieves the TS packets from the stream.
        """
        return self._next_TSPacket()

    def seek(self,offset):
        """Seek to the given offset, which should be a multiple of 188.

        Note that the method does not check the value of 'offset'.
        """
        retval = seek_using_TS_reader(self.tsreader,offset)
        if retval == 1:
            raise TSToolsException,'Error seeking to %d in file %s'%(offset,self.name)

    def read(self):
        """Read the next TS packet from this stream.
        """
        try:
            return self._next_TSPacket()
        except StopIteration:
            raise EOFError

    def write(self, TSPacket tspacket):
        """Write a TS packet to this stream.
        """
        pass

    def find_PAT(self,max=0,verbose=False,quiet=False):
        """Read TS packets to find the (next) PAT.

        If non-zero, `max` is the maximum number of TS packets to scan forwards
        whilst looking. If it is zero, there is no limit.

        If `verbose` is True, then extra information is output. If `quiet` is
        True, then the search will be as quiet as possible.

        Returns (num_read, pat), where `num_read` is how many TS packets were
        read (whether the PAT is found or not), and `pat` is None if no PAT
        was found.

        The new PAT is also saved as self.PAT (replacing, rather than updating,
        any previous self.PAT object).
        """
        cdef pidint_list_p  prog_list
        cdef int            num_read
        if self.tsreader == NULL:
            raise TSToolsException,'No TS stream to read'
        retval = find_pat(self.tsreader,max,verbose,quiet,&num_read,&prog_list)
        if retval == EOF:       # No PAT found
            return (num_read,None)
        elif retval == 1:
            raise TSToolsException,'Error searching for next PAT'
        try:
            pat = PAT()
            for 0 <= ii < prog_list.length:
                pat[prog_list.number[ii]] = prog_list.pid[ii]
            # And remember it on the file as well
            self.PAT = pat
        finally:
            free_pidint_list(&prog_list)
        return (num_read,pat)

    def close(self):
        ## Since we don't appear to be able to call our __dealloc__ "method",
        ## and we're not allowed to call Python methods..
        #if self.tsreader != NULL:
        #    retval = close_TS_reader(&self.tsreader)
        #    if retval != 0:
        #        raise TSToolsException,"Error closing file '%s':"\
        #                " %s"%(self.name,strerror(errno))
        self._close_for_read()
        self.name = None
        self.mode = None

    def __enter__(self):
        return self

    def __exit__(self, etype, value, tb):
        if tb is None:
            # No exception, so just finish normally
            self.close()
        else:
            # Exception occurred, so tidy up
            self.close()
            # And allow the exception to be re-raised
            return False

# ----------------------------------------------------------------------
# vim: set filetype=python expandtab shiftwidth=4:
# [X]Emacs local variables declaration - place us into python mode
# Local Variables:
# mode:python
# py-indent-offset:4
# End:

