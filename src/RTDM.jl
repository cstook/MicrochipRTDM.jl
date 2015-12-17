export rtdm_write, rtdm_read, rtdm_read!, isrtdmok, RTDMInterface

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
  address :: Dict{Symbol,UInt32} # connects symbols to addresses
  iouart  :: IO # serial port microcontroller is connected to
  iopipe  :: IOBuffer # pipe to serialize data for crc and uart
  iopipe2 :: IOBuffer
  buffer1 :: Array{UInt8,1}
  buffer4 :: Array{UInt8,1}
  buffer6 :: Array{UInt8,1}
  buffercrc :: Array{UInt16,1}
  crc :: CRC
  function RTDMInterface(addressdict::Dict{Symbol,UInt32}, iouart::IO)
    new(addressdict, iouart, PipeBuffer(), PipeBuffer(),
      Array(UInt8,1), Array(UInt8,4), Array(UInt8,6),
      Array(UInt16,1), CRC(0xffff,0x00))
  end
end

function Base.show(io::IO, x::RTDMInterface)
  println(io, "Dict{Symbol,UInt32} with ",length(x.address)," entries")
  show(io, x.iouart)
  return nothing
end


function Base.close(i::RTDMInterface)
  close(i.iouart)
  close(i.iopipe)
end

function pipecrc!(i::RTDMInterface, data)
  write(i.iopipe,data)
  while ~eof(i.iopipe)
    i.crc.data = read(i.iopipe, UInt8)
    compute_crc(i.crc)
  end
  return nothing
end

function sendpipewithcrc(i::RTDMInterface)  # always attach and send crc
  while ~eof(i.iopipe)
    byte = read(i.iopipe, UInt8)
    write(i.iopipe2, byte)
    i.crc.data = byte
    compute_crc(i.crc)
  end
  write(i.iopipe2, i.crc.crc)
  write(i.iouart, takebuf_array(i.iopipe2))
  resetcrc!(i)
  return nothing
end

function loadpipe(i::RTDMInterface, bytestoload::Integer, last2crc = bytestoload>1)
  # set last2crc = true to not include last two bytes read in crc calculation
  data = read(i.iouart, UInt8, bytestoload)
  for index in 1:length(data)
    if (index < bytestoload-1) | ~last2crc
      i.crc.data = data[index]
      compute_crc(i.crc)
    end
  end
  write(i.iopipe,data)
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
  loadpipe(i,1)
  replycode = read(i.iopipe, UInt8)
  if replycode != 0x2b  # '+'
    loadpipe(i,6)
    read!(i.iopipe, i.buffer4)
    read!(i.iopipe, i.buffercrc)
    if i.buffer4[1] != 0x24 # '$'
      errorcode = -1
    elseif i.buffer4[2] != 0x45 # 'E'
      errorcode = -1
    elseif i.buffer4[4] != 0x23 # '#'
      errorcode = -1
    elseif i.buffercrc[1] != getcrc(i)
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
  for attempt in 1:retry
    resetcrc!(i)
    write(i.iopipe, communication_link_sanity_check)
    sendpipewithcrc(i)
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      loadpipe(i, 8)
      read!(i.iopipe, i.buffer6)
      read!(i.iopipe, i.buffercrc)
      if getcrc(i) != i.buffercrc[1] # did crc match?
        errorcode = -3
      end
    end
    if errorcode == 0 
      break
    end
  end
  return errorcode == 0
end

const startreadrequest =  b"$m"
const endofmessage = b"#"
const startreadreply =b"$"
function rtdm_read{T}(i::RTDMInterface, ::Type{T}, address::Integer; retry = 1)
  address32 = convert(UInt32,address)
  buffersize16 = UInt16(sizeof(T))
  errorcode = -99
  data = T(0)
  for attempt in 1:retry
    resetcrc!(i)
    # request read
    write(i.iopipe, startreadrequest)
    write(i.iopipe, address32)
    write(i.iopipe, buffersize16)
    write(i.iopipe, endofmessage)
    sendpipewithcrc(i)
    # process reply
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      loadpipe(i, sizeof(T) + 4)
      read!(i.iopipe, i.buffer1)
      data = read(i.iopipe, T)
      read!(i.iopipe, i.buffer1)
      read!(i.iopipe, i.buffercrc)
      if getcrc(i) != i.buffercrc[1]
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

function rtdm_read!{T}(i::RTDMInterface, buffer::Array{T}, address::Integer; retry = 1)
  address32 = UInt32(address)
  buffersize16 = UInt16(sizeof(buffer))
  errorcode = -99
  for attempt in 1:retry
    resetcrc!(i)
    # request read
    write(i.iopipe, startreadrequest)
    write(i.iopipe, address32)
    write(i.iopipe, buffersize16)
    write(i.iopipe, endofmessage)
    sendpipewithcrc(i)
    # process reply
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      loadpipe(i, buffersize16 + 4)
      read!(i.iopipe, i.buffer1) # start code
      read!(i.iopipe, buffer) # data 
      read!(i.iopipe, i.buffer1) # end code
      read!(i.iopipe, i.buffercrc) # crc
      if getcrc(i) != i.buffercrc[1]
        errorcode = -4
      end
    end
    if errorcode == 0 
      break
    end
  end
  checkerrorcode(errorcode,retry)
  return nothing
end

const startwrite = b"$M"
const endofwrite = b"#"

function rtdm_write{T}(i::RTDMInterface, buffer::Array{T}, address::Integer; retry = 1)
  address32 = UInt32(address)
  buffersize16 = UInt16(sizeof(buffer))
  errorcode = -99
  for attempt in 1:retry
    resetcrc!(i)
    # write memory
    write(i.iopipe, startwrite)
    write(i.iopipe, address32)
    write(i.iopipe, buffersize16)
    write(i.iopipe, buffer)
    write(i.iopipe, endofwrite)
    sendpipewithcrc(i)
    # process reply
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      loadpipe(i,6)
      read!(i.iopipe, i.buffer4)
      read!(i.iopipe, i.buffercrc)
      if getcrc(i) != i.buffercrc[1]
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

function rtdm_write(i::RTDMInterface, data, address::Integer; retry = 1)
  address32 = UInt32(address)
  buffersize16 = UInt16(sizeof(data))
  errorcode = -99
  for attempt in 1:retry
    resetcrc!(i)
    # write memory
    write(i.iopipe, startwrite)
    write(i.iopipe, address32)
    write(i.iopipe, buffersize16)
    write(i.iopipe, data)
    write(i.iopipe, endofwrite)
    sendpipewithcrc(i)
    # process reply
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      loadpipe(i,6)
      read!(i.iopipe, i.buffer4)
      read!(i.iopipe, i.buffercrc)
      if getcrc(i) != i.buffercrc[1]
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


function rtdm_write(i::RTDMInterface, data, address::Symbol; retry = 1)
  rtdm_write(i, data, i.address[address]; retry = retry)
end
function rtdm_write{T}(i::RTDMInterface, buffer::Array{T}, address::Symbol; retry = 1)
  rtdm_write(i, buffer, i.address[address]; retry = retry)
end
function rtdm_read!{T}(i::RTDMInterface, buffer::Array{T}, address::Symbol; retry = 1)
  rtdm_read!(i, buffer, i.address[address]; retry = retry)
end
function rtdm_read{T}(i::RTDMInterface, ::Type{T}, address::Symbol; retry = 1)
  rtdm_read(i, T, i.address[address]; retry = retry)
end
