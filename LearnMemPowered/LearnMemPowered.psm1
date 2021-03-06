
$global:memcached_servers = @()
$global:memcached_stored_keys = @()
$global:memcached_exe = join-path (split-path $myinvocation.mycommand.path) "memcached.exe"

<#
 .Synopsis
  Start's a new memcached server in a background job and adds it to the MemPowered module configuration.
 
 .Parameter ip
  IP memcached instance should listen on. Default's to localhost (127.0.0.1).
  
 .Parameter port
  Port memcached instance should listen on.  Default's to a number greater than 11211 (increments with each new server).
 
 .Parameter memory
  Megabytes of memory mecached should use.
#>
function add-server
{
    param ($ip="127.0.0.1", $port=(11212 + $global:memcached_servers.count), $memory=10)

    #Create memcache instance
    $job = start-job -ArgumentList $global:memcached_exe, $ip, $port, $memory -ScriptBlock `
            {
                param($exe, $ip, $port, $memory) & $exe -m $memory -vv -l $ip -p $port  
            }
             
    
    $server_info = new-object psobject | 
                    add-member noteproperty ip $ip -passthru | 
                    add-member noteproperty port $port -passthru | 
                    add-member noteproperty job $job -passthru                    
                    
    Write-Host "Starting memcached instance (port $port, memory $memory MB)"
    
    $global:memcached_servers += $server_info
    
    #Add server to Module config
    add-memcachedserver $ip $port
}
export-modulemember add-server

<#

 .Synopsis
  Shut's down the newest memcached server and removes it from the config.

#>
function remove-server(){
    if($global:memcached_servers.count -eq 0){
        write-error "No memcached servers to remove"
    }else{
        
        $index = $global:memcached_servers.count -1
        $server_info = $global:memcached_servers[$index]
        
        $tmp = @()
        for($i=0;$i -lt $global:memcached_servers.count;$i++){
            if($i -ne $index){
                $tmp += $global:memcached_servers[$i]
            }
        }
        $global:memcached_servers = $tmp
        
        remove-memcachedserver $server_info.ip $server_info.port
        stop-job $server_info.job
        remove-job $server_info.job
    }
}
export-modulemember remove-server

<#

 .Synopsis
  Store's a key/value pair in memcached.  It also keeps a reference to the key so that hit rates can be examined.

#>
function store-data($key, $value){
    set-memcached $key $value -verbose
    
    $global:memcached_stored_keys += $key
}
export-modulemember store-data

function store-randomData($numberOfItems){
    1..$numberOfItems | 
    %{
        $key =  [string] [Guid]::NewGuid()
        $value = [string] [Guid]::NewGuid()
        store-data $key $value
        write-progress "Storing data" "Progress" -percentcomplete (100*$_/$numberOfItems)
    }
}
export-modulemember store-randomData

<#
 .Synopsis
  Retrieves every key stored in memcached (that is referenced) and returned the hit rate.
#>
function retrieve-allData($num){
    $global:memcached_stored_keys |
        % `
            { $success = 0 } `
            { if(get-memcached ([string]$_) -verbose) { [void]$success++ } } `
            { write-host ("Hit rate: " + ($success/($global:memcached_stored_keys.count/100)) + "%") }
}
export-modulemember retrieve-allData

<#
 .Synopsis
  Remove's reference to all key's stored in memcached.
#>
function clear-allData(){
    $global:memcached_stored_keys = @()
}
export-modulemember clear-allData

<#
 .Synopsis
  Shut's down all memcached instances.
#>
function cleanup(){

    $global:memcached_servers | 
        %{
            remove-memcachedserver 127.0.0.1 $_.port
        }
    stop-job *
    remove-job *
    
    $global:memcached_servers = @()
}
export-modulemember cleanup