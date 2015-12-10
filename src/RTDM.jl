export rtdm_write, rtdm_read, rtdm_read!, isrtdmok, RTDMInterface

# include("crc.jl")

type CRC
  crc  :: UInt16 # running crc
  data :: UInt8  # input byte for bit shifting
end

const polynomial = 0xa001
function compute_crc(crc::CRC)
  for i in 1:8
    if ((crc.crc $ crc.data)&0x0001) == 0x0001
      crc.crc = (crc.crc>>>1) $ polynomial
    else
      crc.crc = crc.crc>>>1
    end
    crc.data >>>=1
  end
  return crc.crc
end

immutable RTDMInterface
  address :: Dict{ASCIIString,UInt32} # connects symbols to addresses
  iouart  :: IO # serial port microcontroller is connected to
  iopipe  :: IOBuffer # pipe to serialize data for crc and uart
  buffer4 :: Array{UInt8,1}
  buffer6 :: Array{UInt8,1}
  buffer20 :: Array{UInt8,1}
  crc :: CRC
  function RTDMInterface(addressdict::Dict{ASCIIString,UInt32}, iouart::IO)
    new(addressdict, iouart, PipeBuffer(), 
      Array(UInt8,4), Array(UInt8,6), Array(UInt8,20),CRC(0xffff,0x00))
  end
end

function pipecrc!(i::RTDMInterface, data)
  write(i.iopipe,data)
  while ~eof(i.iopipe)
    i.crc.data = read(i.iopipe, UInt8)
    compute_crc(i.crc)
  end
  return nothing
end


function writewithcrc(i::RTDMInterface, data; computecrc = true)
  write(i.iouart,data)
  if computecrc
    pipecrc!(i, data)
  end
  return nothing
end

function readwithcrc{T}(i::RTDMInterface, ::Type{T}; computecrc = true)
  data = read(i.iouart, T)
  if computecrc
    pipecrc!(i, data)
  end
  return data
end

function readwithcrc!{T}(i::RTDMInterface, data::Array{T}; computecrc = true)
  read!(i.iouart, data)
  if computecrc
    pipecrc!(i, data)
  end
  return nothing
end

function resetcrc!(i::RTDMInterface)
  i.crc.crc = 0xffff
  return nothing
end

getcrc(i::RTDMInterface) = i.crc.crc

function checkforerrorcode(i::RTDMInterface)
  # errorcode = 0   no error
  # errorcode < 0   somthing wrong with received message. from this module.
  # errorcode > 0   error code returned by target.  from microcontroller.
  # returns errorcode and crc up to this point
  resetcrc!(i)
  errorcode = 0
  replycode = readwithcrc(i,UInt8)
  if replycode != UInt8('+')
    readwithcrc!(i, i.buffer4)
    crc = readwithcrc(i, UInt16, computecrc = false)
    if i.buffer4[1] != UInt8('$')
      errorcode = -1
    elseif i.buffer4[2] != UInt8('E')
      errorcode = -1
    elseif i.buffer4[4] != UInt8('#')
      errorcode = -1
    elseif crc != getcrc(i)
      errorcode = -2
    else
      errorcode = convert(Int,i.buffer4[3])
    end
  end
  return errorcode
end

const communication_link_sanity_check = b"$s#"
const linkok = b"$RTDM#"
const clsc_writereplybuffer = Array(UInt8,length(linkok))

function isrtdmok(i::RTDMInterface; retry = 1)
  errorcode = -99
  crc = 0x0000
  for attempt in 1:retry
    resetcrc!(i)
    writewithcrc(i,communication_link_sanity_check)
    writewithcrc(i,getcrc(i),computecrc = false)
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      readwithcrc!(i, i.buffer6)
      crc = readwithcrc(i,UInt16, computecrc = false)
      if crc != getcrc(i)
        errorcode = -3
      end
    end
    if errorcode == 0 
      break
    end
  end
  return errorcode == 0
end


#=


const startreadrequest =  b"$m"
const endofmessage = b"#"
const startreadreply =b"$"
function rtdm_read{T}(io::IO, ::Type{T}, address::Integer; retry = 1)
  address32 = convert(UInt32,address)
  buffersize16 = UInt16(sizeof(T))
  errorcode = -99
  data = T(0)
  for i in 1:retry
    crc = 0xffff
    # request read
    write(io, startreadrequest)
    crc = rtdm_crc(crc, startreadrequest) 
    write(io, address32)
    crc = rtdm_crc(crc, address32)
    write(io, buffersize16)
    crc = rtdm_crc(crc, buffersize16)
    write(io, endofmessage)
    crc = rtdm_crc(crc, endofmessage)
    write(io, crc)
    # process reply
    (errorcode,crc) = checkforerrorcode(io)
    if errorcode == 0
      startcode = read(io, UInt8)
      crc = rtdm_crc(crc, startcode)
      data = read(io, T)
      crc = rtdm_crc(crc, data)
      endcode = read(io, UInt8)
      crc = rtdm_crc(crc, endcode)
      replycrc = read(io, UInt16)
      if replycrc != crc
        errorcode = -4
      end
    end
    if errorcode == 0 
      break
    end
  end
  checkerrorcode(errorcode,retry)
  return data
end

#   reinterpret(UInt8, a, (nb,))

const UInt16buffer = Array(UInt16,1)
function rtdm_read(io::IO, ::Type{UInt16}, address::Integer; retry = 1)
  rtdm_read!(io, UInt16buffer, address, retry=retry)
  return UInt16buffer[1]
end

const buffer2 = Array(UInt8,16)
function rtdm_read{T}(io::IO, ::Type{T}, address::Integer; retry = 1)
  if isbits(T)
    rtdm_read!(io, buffer2[1:sizeof(T)], address, retry=retry)
    return reinterpret(T,buffer2,(div(16,sizeof(T)),))[1]
  else
    buffer = Array(T,1)
    rtdm_read!(io, buffer, address, retry=retry)
    return buffer[1]
  end
end

const startwrite = b"$M"
const endofwrite = b"#"
# const replyok = b"$OK#"
const replyokcrc = rtdm_crc(b"+$OK#")
const writereplybuffer = Array(UInt8,4)

function rtdm_write{T}(io::IO, buffer::Array{T}, address::Integer; retry = 1)
  address32 = UInt32(address)
  buffersize16 = UInt16(sizeof(buffer))
  errorcode = -99
  for i in 1:retry
    crc = 0xffff
    # write memory
    write(io, startwrite)
    crc = rtdm_crc(crc, startwrite)
    write(io, address32)
    crc = rtdm_crc(crc, address32)
    write(io, buffersize16)
    crc = rtdm_crc(crc, buffersize16)
    write(io, buffer)
    crc = rtdm_crc(crc, buffer)
    write(io, endofwrite)
    crc = rtdm_crc(crc, endofwrite)
    write(io, crc)
    # process reply
    (errorcode,crc) = checkforerrorcode(io)
    if errorcode == 0
      writereplybuffer[4] = 0x00
      read!(io, writereplybuffer)
      #crc = rtdm_crc(crc, writereplybuffer) # don't need this
      replycrc = read(io, UInt16)
      if replyokcrc != replycrc
        errorcode = -5
      end
    end
    if errorcode != 0 
      break
    end
  end
  checkerrorcode(errorcode,retry)
  return nothing
end

function rtdm_write(io::IO, data, address::Integer; retry = 1)
  buffer = [data]
  rtdm_write(io, buffer, address, retry=retry)
  return nothing
end

=#