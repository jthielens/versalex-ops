#!/bin/sh
# usage:   mvnurl "group%artifact%version"
# returns: the mavencentral uri for the artifact
mvnurl () {
    local gav group site artifact
    gav=$1
    group=$(echo ${gav%%%*} | sed 's/\./\//g')
    if [ $(echo "$group" | sed -n '/^com\/cleo\//p') ]; then
        if [ $(echo $gav | sed -n '/SNAPSHOT$/p') ]; then
            site=snapshots
        else
            site=releases
        fi
        artifact=$(echo $gav | sed 's/\(.*\)%\(.*\)%\(.*\)/\&g=\1\&a=\2\&v=\3\&e=jar/')
        echo "http://10.10.1.57/nexus/service/local/artifact/maven/redirect?r=$site$artifact"
    else
        site="http://central.maven.org/maven2"
        artifact=$(echo $gav | sed 's/\(.*\)%\(.*\)%\(.*\)/\2\/\3\/\2-\3.jar/')
        echo "$site/$group/$artifact"
    fi
}

# usage:   mvnfile "group%artifact%version"
# returns: the maven filename
mvnfile () {
    echo $1 | sed 's/\(.*\)%\(.*\)%\(.*\)/\2-\3.jar/'
}

# usage:   mvndownload "group%artifact%version" [$cache]
# returns: /usr/local/bin/$artifact
mvndownload () {
    local url asset cache
    url=$(mvnurl $1)
    cache=$2
    asset=$(mvnfile $1)
    echo $(download $url $asset $cache)
}

# usage:   githuburl "jthielens/versalex-ops" [$branch] "service/cleo-service"
# returns: the github URL for file in repo
githuburl () {
    local repo branch path
    repo=$1
    branch=master
    path=$2
    if [ -n "$3" ]; then branch=$2; path=$3; fi
    echo "https://raw.githubusercontent.com/$repo/$branch/$path"
}

# usage:   githubdownload "github-user/repo" [$branch] "path/artifact" [$cache]
# returns: /usr/local/bin/$artifact
# note:    3 argument form defaults $branch if $cache is a directory, otherwise defaults $cache
githubdownload () {
    local repo branch path artifact cache
    repo=$1; shift
    if [ $# -ge 3 ]; then
        branch=$1
        path=$2
        cache=$3
    elif [ $# -eq 2 ]; then
        if [ -d $2 ]; then
            branch=master
            path=$1
            cache=$2
        else
            branch=$1
            path=$2
            cache=/usr/locall/bin
        fi
    else
        branch=master
        path=$1
        cache=/usr/local/bin
    fi
    artifact=${path##*/}
    artifact=$(download $(githuburl "$repo" "$branch" "$path") $artifact $cache)
    if [ "$(id -u)" != "0" ]; then
        sudo chmod a+x "$artifact"
    else
        chmod a+x "$artifact"
    fi
    echo $artifact
}

# usage:   githubasseturl user/repo release asset
# returns: the github asset download URL for the asset and release
githubasseturl () {
    local repo release asset
    repo=$1
    release=$2
    asset=$3
    echo "https://github.com/$repo/releases/download/$release/$asset"
}

# usage:   githubassetdownload user/repo release asset [cache]
# returns: $cache/$asset
githubassetdownload () {
    local repo release asset cache
    repo=$1
    release=$2
    asset=$3
    cache=$4
    echo $(download $(githubasseturl "$repo" "$release" "$asset") $asset $cache)
}

# usage:   cleorelease $product
# returns: the current release of $product
cleorelease () {
    case "$1" in
    "vltrader") echo 5.2;;
    "harmony")  echo 5.2;;
    "unify")    echo 2.3;;
    "vlproxy")  echo 3.4;;
    esac
}

# usage:   nexusname $product
# returns: the nexus name $product
nexusname () {
    case "$1" in
    "vltrader") echo VLTrader;;
    "harmony")  echo Harmony;;
    "unify")    echo Unify;;
    "vlproxy")  echo VLProxy
    esac
}

# usage:   jre $release
# returns: 1.7 if $release is less than 5.3, otherwise 1.8
jre () {
    local release
    release=$1
    if [ $(echo $release/5.3 | tr / \\n | sort | head -n 1) = "5.3" ]; then
        echo 1.8
    else
        echo 1.7
    fi
}

# usage:   cleourl "product" ["release"]
# returns: the download URL for Cleo product "product", optionally including "release"
# note:    supports Linux/Ubuntu for Unify
cleourl () {
    local product release jre os
    product=$1
    release=$2
    os="Linux"
    if [ "$release" = "$(cleorelease $product)" -o -z "$release" ]; then release=''; else release=_$release; fi
    # if [ "$product" = "unify" -o "$release" ]; then jre=1.7; else jre=1.6; fi
    jre=$(jre $release)
    if [ "$product" = "unify" ]; then os="Ubuntu"; fi
    echo "http://www.cleo.com/SoftwareUpdate/$product/release$release/jre$jre/InstData/$os(64-bit)/VM/install.bin"
}

# usage:   patchurl "product" "release" "patch"
# returns: the download URL for Cleo VersaLex patch "patch" for "release"
patchurl () {
    local product release patch
    product=$1
    release=$2
    patch=$3
    echo "http://www.cleo.com/Web_Install/PatchBase_$release/$product/$patch/$patch.zip"
}

# usage:   nexusurl "product" ["release"]
# returns: the download URL for Cleo product "product", optionally including "release", from Nexus
# note:    supports Linux/Ubuntu for Unify
nexusurl () {
    local product release os jre contd
    product=$(nexusname $1)
    release=$2
    os="linux64"
    jre=$(jre $release | tr -d .)
    contd="10.10.1.57"
    if [ "$product" = "Unify" ]; then os="ubuntu"; fi
    echo "http://$contd/nexus/service/local/repositories/releases/content/com/cleo/installers/$product/$release/$product-$release-$os-jre$jre.bin"
}

# usage:   mysqlurl "version"
# returns: the download URL for MySQL driver "version"
mysqlurl () {
    local version
    version=$1
    echo "http://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-$version.tar.gz"
}

# usage:   speak short-message long-message
# does:    echo a message to stderr depending on "quiet" variable
speak () {
    short=$1
    long=$2
    if [ -z "$quiet" ]; then
        echo $long 1>&2
    elif [ "$quiet" = short -a "$short" ]; then
        echo $short 1>&2
    fi
}

# usage:   download $url $target [$cache]
# returns: the target file name in the $cache (default is $HOME/.cleo/cache)
download () {
    local url target cache tag tagfile
    url=$1
    target=$2
    cache=${3:-"$HOME/.cleo/cache"}
    if [ ! -e $cache ]; then mkdir -p $cache; fi
    # get the current etag
    tagfile="$cache/$target.etag"
    if [ -s $tagfile ]; then
        tag="\"$(cat $tagfile 2>/dev/null)\""
    else
        tag="\"null\""
    fi
    # attempt to download the target using current etag, if any
    speak "checking $target..." \
          "downloading $cache/$target from $url (current etag=$(cat $tagfile 2>/dev/null))"
    if wget -nv -S --header="If-None-Match: $tag" -O $cache/$target.tmp "$url" 2> $cache/$target.tmp.h; then
        tag=$(sed -n '/ETag/s/.*ETag: *"\(.*\)".*/\1/p' $cache/$target.tmp.h)
        if [ "$tag" ]; then
            echo $tag > $tagfile
        fi
        if [ -s $cache/$target.tmp ]; then
            mv -f $cache/$target.tmp $cache/$target
            speak "$target updated" \
                  "successful download: $cache/$target (new etag=$tag)"
        else
          speak "empty download: $target not updated" \
                "empty download: reusing cached $cache/$target"
        fi
    elif grep 'HTTP/1\.1 304' $cache/$target.tmp.h >/dev/null 2>&1; then
        speak '' "file not modified: reusing cached $cache/$target"
    else
        speak "connection error: $target not updated" \
              "connection error: reusing cached $cache/$target" 1>&2
    fi
    # rm $cache/$target.tmp.h 2>/dev/null
    rm $cache/$target.tmp   2>/dev/null
    echo $cache/$target
}

# usage:   cleodownload $product [$release] [$cache]
# returns: the install file name
cleodownload () {
    local product release cache
    product=$1
    release=${2:-$(cleorelease $product)}
    cache=$3
    echo $(download $(cleourl $product $release) "$product$release.bin" $cache)
}

# usage:   patchdownload $product $release $patch [$cache]
# returns: the install file name
patchdownload () {
    local product release patch [$cache]
    product=$1
    release=$2
    patch=$3
    cache=$4
    echo $(download $(patchurl $product $release $patch) "$product$release.$patch.zip" $cache)
}

# usage:   nexusdownload $product [$release] [$cache]
# returns: the install file name
nexusdownload () {
    local product release cache
    product=$1
    release=${2:-$(cleorelease $product)}
    cache=$3
    echo $(download $(nexusurl $product $release) "$product$release.nexus.bin" $cache)
}

# usage:   mysqldownload $version [$cache]
# returns: the downloaded install file name
mysqldownload () {
    local version cache
    version=$1
    cache=$2
    echo $(download $(mysqlurl $version) "mysql-connector.tar.gz" $cache)
}

# usage:   issuerfiles [issuerdir]
# returns: nothing, but creates the crt, key, and cnf files if needed
#          issuerdir defaults to $HOME
issuerfiles() {
    local issuerdir
    issuerdir=${1:-$HOME}
    if ! [ -e $issuerdir/vagrant.crt ]; then
        tee $issuerdir/vagrant.crt <<END >/dev/null
-----BEGIN CERTIFICATE-----
MIIDgTCCAmmgAwIBAgIJAIxWZLjTd3mLMA0GCSqGSIb3DQEBBQUAMFcxCzAJBgNV
BAYTAlVTMQswCQYDVQQIDAJJTDETMBEGA1UEBwwKTG92ZXMgUGFyazENMAsGA1UE
CgwEQ2xlbzEXMBUGA1UEAwwOVmFncmFudCBJc3N1ZXIwHhcNMTQwMzE4MDAxOTI3
WhcNMTYwMzE3MDAxOTI3WjBXMQswCQYDVQQGEwJVUzELMAkGA1UECAwCSUwxEzAR
BgNVBAcMCkxvdmVzIFBhcmsxDTALBgNVBAoMBENsZW8xFzAVBgNVBAMMDlZhZ3Jh
bnQgSXNzdWVyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5PnT/9w0
StHoy0+DpuqLTmKb7WCAAKDnQjUSAhQCn0wAxJEv2PBVcf4WW1Gq/fJ4mAi0I8ul
cAoU7p+WJMnrPTejGNCURjgoH3i+FVsAe3wRC3ENdFDdja8MPLUIaAypriAU/w5Y
zdJiLr8WsIrX7PwGPGjkvUceT+pHvVAwiedpFGDyR6W/yilPkvqaddk72zKEkj8D
U/GFW1Z1ctTV56VVCM6qSxNPKJY7nu5lD5JEIBw438gBrbVvcHxkqTPr//+vIGUK
R13qWvBzZOYE00kzFDA2E5Pe7RHRaVF/rC+IOhM6BireFMycoqiaysJEH7Vkje8f
4n6KL1eOtfZUSwIDAQABo1AwTjAdBgNVHQ4EFgQU2xxNZ0s5TcPRo03yT9Y7rENj
eBUwHwYDVR0jBBgwFoAU2xxNZ0s5TcPRo03yT9Y7rENjeBUwDAYDVR0TBAUwAwEB
/zANBgkqhkiG9w0BAQUFAAOCAQEAx9vrxSnOvrXfoP8g0kRo21PIfdFc3xeD+rb1
ZJwccAqb8KyMgZgd8nIloLVOiV3jP1sQRrUosj2iPe2N51XJol9a38yzsuP8NHMa
7GSkxg4OzE4R12YZRRtkzRlm2sB4AtmPgCwHYtQ3DetMyKvpRElhpsPlivIDnodO
UHegL7G0VQxHeuCeeFb90oYifLaPgbY/6iTDo/dnVlQMAksjwqlXzDpDKic5dAFs
tYtPGgNjjLSWOYAvERyZwHJWG+5t99HJj60wvNQhK8FRBKwbbTEyoR6/2HZLLHZO
5nn62NFYt6zNefXnCgmZ/yq5KIzhk1trg7qQYvqktd9aqxzkKA==
-----END CERTIFICATE-----
END
    fi
    if ! [ -e $issuerdir/vagrant.key ]; then
        tee $issuerdir/vagrant.key <<END >/dev/null
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDk+dP/3DRK0ejL
T4Om6otOYpvtYIAAoOdCNRICFAKfTADEkS/Y8FVx/hZbUar98niYCLQjy6VwChTu
n5Ykyes9N6MY0JRGOCgfeL4VWwB7fBELcQ10UN2Nrww8tQhoDKmuIBT/DljN0mIu
vxawitfs/AY8aOS9Rx5P6ke9UDCJ52kUYPJHpb/KKU+S+pp12TvbMoSSPwNT8YVb
VnVy1NXnpVUIzqpLE08oljue7mUPkkQgHDjfyAGttW9wfGSpM+v//68gZQpHXepa
8HNk5gTTSTMUMDYTk97tEdFpUX+sL4g6EzoGKt4UzJyiqJrKwkQftWSN7x/ifoov
V4619lRLAgMBAAECggEAJU+MOvnvz21K6K4pPq6jSn+I9vItiWyuojwxlgMatkhV
K7KYwFnRIoULsY+qND0pZ2SrrdWGPK534LZCafY5Db2eJvH95z9JUm+DUcmFV5nM
0Td3wMdYgrjOXqoFF6dQkt4JbdIxqEAq3YEnula1fplGjttswmbvSohbbj692gp7
MOYsLixA0bKJiRRMARLNCa9feM5cswJJsBud8qx90S2UIEIzFcTuhcTIGhAH4MH9
JQysudxuUhtGnNBfO+2idOvhBR6gwu+h+EFnDThYiFX1AKtV3pSMWgWFTX0D86nC
N+V2FYxaH6/YBnZtXGvQlonMwHzGFB+R0HWrmzZT4QKBgQD/nDI6BO27H7t4xnkZ
WsW/ZXUNvoCuhBkP67qJPHAQU64g6OXM0Ka1uMm2y+X9U9kfrYFgrSl8Cm6cmHoc
0tSfAHKyG1rQM3E/B1ABjizQSu1BpK25qiAMZbo4/j3Yl1eswwiUvtVMf5jG8GeX
Y3SuMWU2l4+T22RVO7PDFA+N0QKBgQDlUzuE4TaRbqI2gWF5sIABitmOUM+USBc/
2TMdUyA5KAJLpTYxBboL+8QJJ7MjITN5qxBcrgA0aCWOi2r3ZzdIJHvlxEBVzNx3
W4EzkVyzvLoS+1T5QveHGSUHsofP0WqFxbnucRuEA3nK8wpJ7wGFejrov15DTF3h
0K03B/P7WwKBgQCH9mGREwYRPvPNbmUD45DEGgeFZAu2yHU8TrtOPGOvi5NX1gpG
Q8Ypaz2Aijyv32Xiv7vN3M3wOOxVR5XMtyh52xcnPf20OWjHifA4o5OayAAjpqDx
3Vhmv8WqgzIKf5YXQzbRSCDVLBnr1/yCPljWP1gDDeNFVrGr1LHt1kHfwQKBgQCn
y7QEMYns9eeJPDfng4bWGhO/t097rxgb5sAo19b/G1A6q2MwkYElHY2+KSdBMBzr
DIkHV2Xc8stwNoEJD6P6jH9/io6MeT5jszehVN5gwVnhY7c0P5TAbFyU+kO3gwKP
aTL3zhkVCjoGjrjbih8x3FLYVJYTZgBXp4nmd1JFewKBgB6niKLD268YB7gX8Rhw
l8mUDvqdfScfSg6DSC58SyXZkxhnQC7NQ9fp6YLcYbbE8gfTZnnK6NjCemcM6jO1
84rbYEFVPTgEfW7OqHimkLpDIJIB3EE0ehsSsL8lJAkLvkfNh9W/FrVl+oaMnzbQ
4LrOiyCNJlIRBkRgqciMLwzA
-----END PRIVATE KEY-----
END
    fi
    if ! [ -e $issuerdir/vagrantssl.cnf ]; then
        tee $issuerdir/vagrantssl.cnf <<END >/dev/null
#
# OpenSSL example configuration file.
# This is mostly being used for generation of certificate requests.
#

# This definition stops the following lines choking if HOME isn't
# defined.
HOME                    = .
RANDFILE                = $ENV::HOME/.rnd

# Extra OBJECT IDENTIFIER info:
#oid_file               = $ENV::HOME/.oid
oid_section             = new_oids

# To use this configuration file with the "-extfile" option of the
# "openssl x509" utility, name here the section containing the
# X.509v3 extensions to use:
# extensions            =
# (Alternatively, use a configuration file that has only
# X.509v3 extensions in its main [= default] section.)

[ ssl_cert ]

keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = critical,serverAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer

[ as2_sign ]

keyUsage = critical,digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer

[ as2_encrypt ]

keyUsage = critical,keyEncipherment
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
END
    fi
}

# usage:   issue subject key [issuerdir]
# returns: nothing, but creates key.{key,req,crt,p8}
#          issuerdir defaults to $HOME
issue() {
    local subject key issuerdir
    subject=$1
    key=$2
    issuerdir=${3:-$HOME}
    issuerfiles $issuerdir
    openssl req -new -newkey rsa:2048 -nodes \
        -subj "$subject" -keyout $key.key -out $key.req 2>/dev/null
    openssl x509 -req -in $key.req -extfile $issuerdir/vagrantssl.cnf \
        -days 365 -extensions ssl_cert \
        -CA $issuerdir/vagrant.crt -CAkey $issuerdir/vagrant.key -set_serial \
        0x`uuidgen|sed 's/-//g'` -out $key.crt 2>/dev/null
    openssl pkcs8 -topk8 -in $key.key  -out $key.p8  -passout pass:cleo 2>/dev/null
}

# usage:   cleoapi [get|post] [user:pass@][host:port] resource [data]
# returns: the get/post output
#          host:port defaults to localhost:5080
cleoapi() {
    local verb user password host resource data
    if [ "$1" = "get" -o "$1" = "post" ]; then verb=$1; shift; fi
    if [ ! "${1#*@}" = "$1" ]; then
        host=${1#*@}
        user=${1%%@*}
        password=${user#*:}
        user=${user%%:*}
        shift;
    elif [ ! "${1#*[.:]}" = "$1" ]; then
        host=$1
        shift
    fi
    if [ -z "$user"     ]; then user=administrator ; fi
    if [ -z "$password" ]; then password=Admin     ; fi
    if [ -z "$host"     ]; then host=localhost:5080; fi
    resource=$1
    data=$2
    if [ -z "$verb" ]; then if [ "$data" ]; then verb=post; else verb=get; fi fi
    if [ "$data" ]; then data=--post-data="$data"; fi
    wget --user=$user --password=$password --auth-no-challenge --header='Content-Type: application/json' $data -O - -q http://$host/api/$resource
}

# returns: nothing, but creates key.{key,req,crt,p8}
#          issuerdir defaults to $HOME

case $1 in
mvnurl)              shift; mvnurl $@;;
mvnfile)             shift; mvnfile $@;;
mvndownload)         shift; mvndownload $@;;
githuburl)           shift; githuburl $@;;
githubdownload)      shift; githubdownload $@;;
githubasseturl)      shift; githubasseturl $@;;
githubassetdownload) shift; githubassetdownload $@;;
cleorelease)         shift; cleorelease $@;;
nexusname)           shift; nexusname $@;;
jre)                 shift; jre $@;;
cleourl)             shift; cleourl $@;;
patchurl)            shift; patchurl $@;;
nexusurl)            shift; nexusurl $@;;
mysqlurl)            shift; mysqlurl $@;;
speak)               shift; speak $@;;
download)            shift; download $@;;
cleodownload)        shift; cleodownload $@;;
patchdownload)       shift; patchdownload $@;;
nexusdownload)       shift; nexusdownload $@;;
mysqldownload)       shift; mysqldownload $@;;
issuerfiles)         shift; issuerfiles $@;;
issue)               shift; issue $@;;
cleoapi)             shift; cleoapi $@;;
esac
