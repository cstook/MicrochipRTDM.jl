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
  address :: Dict{ASCIIString,UInt32} # connects symbols to addresses
  iouart  :: IO # serial port microcontroller is connected to
  iopipe  :: IOBuffer # pipe to serialize data for crc and uart
  buffer1 :: Array{UInt8,1}
  buffer4 :: Array{UInt8,1}
  buffer6 :: Array{UInt8,1}
  buffercrc :: Array{UInt16,1}
  crc :: CRC
  function RTDMInterface(addressdict::Dict{ASCIIString,UInt32}, iouart::IO)
    new(addressdict, iouart, PipeBuffer(), 
      Array(UInt8,1), Array(UInt8,4), Array(UInt8,6),
      Array(UInt16,1), CRC(0xffff,0x00))
  end
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
  if replycode != 0x2b  # '+'
    readwithcrc!(i, i.buffer4)
    readwithcrc!(i, i.buffercrc, computecrc = false)
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
    writewithcrc(i, communication_link_sanity_check)
    writewithcrc(i,getcrc(i), computecrc = false)
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      readwithcrc!(i, i.buffer6)
      readwithcrc!(i, i.buffercrc, computecrc = false)
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
    writewithcrc(i, startreadrequest)
    writewithcrc(i, address32)
    writewithcrc(i, buffersize16)
    writewithcrc(i, endofmessage)
    writewithcrc(i, getcrc(i), computecrc = false)
    # process reply
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      readwithcrc!(i, i.buffer1)  # read start code
      data = readwithcrc(i, T)
      readwithcrc!(i, i.buffer1) # read end code
      readwithcrc!(i, i.buffercrc, computecrc = false)
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
    writewithcrc(i, startreadrequest)
    writewithcrc(i, address32)
    writewithcrc(i, buffersize16)
    writewithcrc(i, endofmessage)
    writewithcrc(i, getcrc(i), computecrc = false)
    # process reply
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      readwithcrc!(i, i.buffer1)  # read start code
      readwithcrc!(i, buffer)
      readwithcrc!(i, i.buffer1) # read end code
      readwithcrc!(i, i.buffercrc, computecrc = false)
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
# const replyok = b"$OK#"
# const replyokcrc = 0x084c # rtdm_crc(b"+$OK#")

function rtdm_write{T}(i::RTDMInterface, buffer::Array{T}, address::Integer; retry = 1)
  address32 = UInt32(address)
  buffersize16 = UInt16(sizeof(buffer))
  errorcode = -99
  for attempt in 1:retry
    resetcrc!(i)
    # write memory
    writewithcrc(i, startwrite)
    writewithcrc(i, address32)
    writewithcrc(i, buffersize16)
    writewithcrc(i, buffer)
    writewithcrc(i, endofwrite)
    writewithcrc(i, getcrc(i), computecrc = false)
    # process reply
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      readwithcrc!(i, i.buffer4)
      readwithcrc!(i, i.buffercrc, computecrc = false)
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
    writewithcrc(i, startwrite)
    writewithcrc(i, address32)
    writewithcrc(i, buffersize16)
    writewithcrc(i, data)
    writewithcrc(i, endofwrite)
    writewithcrc(i, getcrc(i), computecrc = false)
    # process reply
    errorcode = checkforerrorcode(i)
    if errorcode == 0
      readwithcrc!(i, i.buffer4)
      readwithcrc!(i, i.buffercrc, computecrc = false)
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
