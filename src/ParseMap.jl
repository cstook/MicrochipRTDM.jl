# parse .map file into dict of external symbols

export microchip_parsemap

function returnvalidmapfile(filenameorprojectdirectory::ASCIIString, maptype::ASCIIString = "production")  
  # filenameorprojectdirectory may be either the X project directory or the .map file
  # maptype: if project directory is specified maptype may be either "production" or "debug" 
  if isfile(filenameorprojectdirectory)
    (f,e) = splitext(filenameorprojectdirectory)
    if e == ".map"
      return filenameorprojectdirectory
    else
      error("not a .map file")
    end
  else
    if filenameorprojectdirectory[end] == '/'
      filenameorprojectdirectory = filenameorprojectdirectory[1:end-1]
    end
    (f,e) = splitext(basename(filenameorprojectdirectory))
    if e != ".x"
      error("directory must end in .x")
    end
    canidatefile = joinpath(filenameorprojectdirectory,"dist/default/$maptype","$f.X.$maptype.map")
    if isfile(canidatefile)
      return canidatefile
    else
      error(".X.$maptype.map file not found in dist/default/$maptype directory")
    end
  end
end

function microchip_parsemap(filenameorprojectdirectory::ASCIIString, maptype::ASCIIString = "production")
  filename = returnvalidmapfile(filenameorprojectdirectory)
  symboldict = Dict()
  open(filename) do iofile
    line = readline(iofile)
    while ~ismatch(r"External Symbols in Data Memory \(by address\):",line) && ~eof(iofile)
      line = readline(iofile)
    end
    while ~ismatch(r"0x([0-9a-f]{4,4})\s*_(\S*)",line) && ~eof(iofile)
      line = readline(iofile)
    end
    m = match(r"0x([0-9a-f]{4,4})\s*_(\S*)",line)
    while m!=nothing  && ~eof(iofile)
      address = m.captures[1]
      name = m.captures[2]
      push!(symboldict,name=>parse(UInt32,address,16))
      line = readline(iofile)
      m = match(r"0x([0-9a-f]{4,4})\s*_(\S*)",line)
    end
  end
  return symboldict
end     