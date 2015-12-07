export rtdm_write, rtdm_read, rtdm_read!, isrtdmok

include("crc.jl")
function checkforerrorcode(io::IO)
  # errorcode = 0   no error
  # errorcode < 0   somthing bad happened, might want to retry command
  # errorcode > 0   error code returned by target
  # returns errorcode and crc up to this point
  crc = 0xffff
  errorcode = 0
  replycode = read(io,UInt8)
  crc = rtdm_crc(crc,replycode)
  if replycode != UInt8('+')  
    errorbuffer = Array(UInt8,4)      
    read!(io,errorbuffer) 
    crc = rtdm_crc(crc,errorbuffer)
    replycrc = read(io,UInt16)
    if errorbuffer[1] != UInt8('$')
      errorcode = -1
    elseif errorbuffer[2] != UInt8('E')
      errorcode = -1
    elseif errorbuffer[4] != UInt8('#')
      errorcode = -1
    elseif crc != replycrc
      errorcode = -2
    else
      errorcode = convert(Int,errorbuffer[3])
    end
  end
  return (errorcode,crc)
end

function isrtdmok(io::IO; retry = 1)
  const communication_link_sanity_check = b"$s#"
  const linkok = b"$RTDM#"
  const replybuffer = Array(UInt8,length(linkok))
  errorcode = -99
  for i in 1:retry
    crc = 0xffff
    write(io,communication_link_sanity_check)
    write(io,rtdm_crc(crc, communication_link_sanity_check))
    (errorcode,crc) = checkforerrorcode(io)
    if errorcode == 0
      replybuffer[6] = 0x00  # make sure we actualy read the value
      read!(io,replybuffer)
      crc = rtdm_crc(crc,replybuffer)
      replycrc = read(io,UInt16)
      if replycrc != crc
        errorcode = -3
      end
    end
    if errorcode == 0 
      break
    end
  end
  return errorcode == 0
end

function rtdm_read!{T}(io::IO, buffer::Array{T}, address::Integer; retry = 1)
  const startreadrequest =  b"$m"
  const endofmessage = b"#"
  const startreadreply =b"$"
  address32 = convert(UInt32,address)
  buffersize16 = UInt16(sizeof(buffer))
  errorcode = -99
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
      read!(io, buffer)
      crc = rtdm_crc(crc, buffer)
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
  return nothing
end

function rtdm_read{T}(io::IO, ::Type{T}, address::Integer; retry = 1)
  buffer = Array(T,1)
  rtdm_read!(io, buffer, address, retry=retry)
  return buffer[1]
end

function rtdm_write{T}(io::IO, buffer::Array{T}, address::Integer; retry = 1)
  const startwrite = b"$M"
  const endofwrite = b"#"
  const replyok = b"$OK#"
  const replyokcrc = rtdm_crc(b"+$OK#")
  replybuffer = Array(UInt8,4)
  address32 = convert(UInt32,address)
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
      replybuffer[4] = 0x00
      read!(io, replybuffer)
      #crc = rtdm_crc(crc, replybuffer) # don't need this
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
