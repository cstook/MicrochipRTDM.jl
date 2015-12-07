# Exception handler for RTDM interface

type RTDMError <: Exception
  errorcode :: Int
  tries     :: Int
end

function Base.showerror(io::IO, e::RTDMError)
  errortext = ""
  if e.errorcode > 0
    errortext = "targer replied with error code $(e.errorcode)"
  elseif e.errorcode == -1
    errortext = "malformed response"
  elseif e.errorcode == -2
    errortext = "error response crc fail"
  elseif e.errorcode == -3
    errortext = "communication link sanity check fail"
  elseif e.errorcode == -4
    errortext = "read fail"
  elseif e.errorcode == -5
    errortext = "write fail"
  end
  print(io, "RTDMError: ",errortext," (",e.tries," retries)")
end

function checkerrorcode(errorcode::Int, tries::Int)
  if errorcode != 0
    throw(RTDMError(errorcode,tries))
  end
  return nothing
end


