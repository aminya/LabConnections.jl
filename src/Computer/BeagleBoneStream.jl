export BeagleBoneStream, init_devices!

const BB_READ = Int32(0)
const BB_WRITE = Int32(1)
const BB_INIT = Int32(2)

struct BeagleBoneStream <: LabStream
    devices::Array{AbstractDevice,1}
    sendbuffer::Array{Tuple,1}
    readbuffer::Array{Tuple,1}
    stream::TCPSocket
end

function BeagleBoneStream(addr::IPAddr, port::Int64=2001)
    clientside = connect(addr, port)
    BeagleBoneStream(AbstractDevice[], Tuple[], Tuple[], clientside)
end

#For BeagleBoneStream we can directly serialize the data, other streams might want to send binary data
serialize(bbstream::BeagleBoneStream, cmd) = serialize(bbstream.stream, cmd)

function init_devices!(bbstream::BeagleBoneStream, devs::AbstractDevice...)
    for dev in devs
        if dev ∉ bbstream.devices
            setstream!(dev, bbstream)
            push!(bbstream.devices, dev)
            initialize(dev)
            # Send to beaglebone 2: initialize, 1 device, (name, index)
            # TODO create proper functionality to initialize
            readcmd = getreadcommand(bbstream, dev)
            name = readcmd[1]::String
            idx = readcmd[2]::Integer
            serialize(bbstream.stream, (BB_INIT, Int32(1), (name, Int32(idx))))

            setupwrite = getsetupwrite(bbstream, dev)
            if setupwrite  !== nothing
                name = setupwrite[1]::String
                idx = setupwrite[2]::Integer
                commands = setupwrite[3]::Tuple
                serialize(bbstream.stream, (BB_WRITE, Int32(1), (name, Int32(idx), commands)))
            end
        else
            @warn "Device $dev already added to a stream"
        end
    end
    return
end

function send(bbstream::BeagleBoneStream)
    ncmds = length(bbstream.sendbuffer)
    serialize(bbstream.stream, (BB_WRITE, Int32(ncmds), bbstream.sendbuffer...))
    empty!(bbstream.sendbuffer)
    return
end
#TODO know the types of outputs some way
function read(bbstream::BeagleBoneStream)
    ncmds = length(bbstream.readbuffer)
    serialize(bbstream.stream, (BB_READ, Int32(ncmds), bbstream.readbuffer...))
    empty!(bbstream.readbuffer)
    vals, timestamps = deserialize(bbstream.stream)
    length(vals) == ncmds || error("Wrong number of return values in $vals on request $(bbstream.readbuffer)")
    #TODO Do something with timestamps
    return (vals...,) #Converting from array to tuple
end

#The following are for interal use only
function send(bbstream::BeagleBoneStream, cmd)
    allcmds = (BB_WRITE, Int32(1), cmd)
    println("Sending single command: $allcmds")
    serialize(bbstream.stream, allcmds)
    return
end
function read(bbstream::BeagleBoneStream, cmd)
    allcmds = (BB_READ, Int32(1), cmd)
    println("Sending single command: $allcmds")
    serialize(bbstream.stream, allcmds)
    vals, timestamps = deserialize(bbstream.stream)
    length(vals) == 1 || error("Wrong number of return values in $vals on request $cmd")
    #TODO Do something with timestamps
    return vals[1], timestamps[1]
end
