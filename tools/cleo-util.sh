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
    "vltrader") echo 5.3;;
    "harmony")  echo 5.3;;
    "unify")    echo 2.3;;
    "vlproxy")  echo 3.5;;
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
    if [ -z "$release" -o "$(echo $release/5.3 | tr / \\n | sort | head -n 1)" = "5.3" ]; then
        echo 1.8
    else
        echo 1.7
    fi
}

# usage:   cleourl "product" ["release"] ["os"]
# returns: the download URL for Cleo product "product", optionally including "release"
# note:    supports Linux/Ubuntu for Unify
cleourl () {
    local product release jre os ext
    product=$1
    release=$2
    os=Linux
    os=${3:-Linux}
    ext=bin
    if [ "$os" = "Windows" ]; then ext=exe; fi
    if [ "$release" = "$(cleorelease $product)" -o -z "$release" ]; then release=''; else release=_$release; fi
    # if [ "$product" = "unify" -o "$release" ]; then jre=1.7; else jre=1.6; fi
    jre=$(jre $release)
    if [ "$product" = "unify" ]; then os="Ubuntu"; fi
    echo "http://www.cleo.com/SoftwareUpdate/$product/release$release/jre$jre/InstData/$os(64-bit)/VM/install.$ext"
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

# usage:   nexusurl "product" ["release"] ["os"]
# returns: the download URL for Cleo product "product", optionally including "release", from Nexus
# note:    supports Linux/Ubuntu for Unify
nexusurl () {
    local product release os jre contd ext
    product=$(nexusname $1)
    release=$2
    if [ "$3" = "Windows" ]; then os=windows64; ext=exe; else os=linux64; ext=bin; fi
    jre=$(jre $release | tr -d .)
    contd="10.10.1.57"
    if [ "$product" = "Unify" ]; then os="ubuntu"; fi
    echo "http://$contd/nexus/service/local/repositories/releases/content/com/cleo/installers/$product/$release/$product-$release-$os-jre$jre.$ext"
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
    local product release patch cache
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
# note:    issuer generated with openssl req -new -x509 -days 3650 -keyout new.key -out newkey.crt -newkey rsa:2048 -nodes -subj "/C=US/O=Cleo/CN=Demo Issuer"
# returns: nothing, but creates the crt, key, and cnf files if needed
#          issuerdir defaults to $HOME
issuerfiles() {
    local issuerdir
    issuerdir=${1:-$HOME}
    if ! [ -e $issuerdir/vagrant.crt ]; then
        tee $issuerdir/vagrant.crt <<END >/dev/null
-----BEGIN CERTIFICATE-----
MIIDNzCCAh+gAwIBAgIJAKmCihK2dUeDMA0GCSqGSIb3DQEBCwUAMDIxCzAJBgNV
BAYTAlVTMQ0wCwYDVQQKDARDbGVvMRQwEgYDVQQDDAtEZW1vIElzc3VlcjAeFw0x
NjA3MDYxNDU4MzRaFw0yNjA3MDQxNDU4MzRaMDIxCzAJBgNVBAYTAlVTMQ0wCwYD
VQQKDARDbGVvMRQwEgYDVQQDDAtEZW1vIElzc3VlcjCCASIwDQYJKoZIhvcNAQEB
BQADggEPADCCAQoCggEBAL+ZS/cW7sUueiH8fEyRkIJCLa8Fs22R/8/f1PZj7uuR
L+MvGAjARaVNGv1bPN/sCb4yNMvUwJl3Z8UBzQWKohAk43x0M4P31oL9i2ypWLYD
v9R6c5GzBNVonJHZVoIFTb5a+EQ4eo7X+wxJIh0UocDRZXP1DtcbwI+eFEGuuTwc
08PibnJ8tEyKhRqFteCARB/QAUXchysB1WM/oWVg/meEyAWL9os1JDGlv9+jI+he
sU6yxo/7e07xNo+pw6INeF1zeK1FZ96oawz1QT0S9C86eXxyEeevVJAWNRHOMXYB
74kgaOhDU+f7DTKC6w1ogfZLh3BrAmOGHmP9b19QqdcCAwEAAaNQME4wHQYDVR0O
BBYEFOdhiP1ylNRfKnd+v2dOqfpqeLfTMB8GA1UdIwQYMBaAFOdhiP1ylNRfKnd+
v2dOqfpqeLfTMAwGA1UdEwQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAIoAIAtA
EjicRYSwkoW4Qx2zo8+i5eobkjZZagJZsAurNODxk44F2Pu54MYG8Oq4epzsKdwk
ws2hA+93RCq7MMrQAAdHlwJQLL3+wMLpg1OMxpnIFBFn8HyDRdUHnvnKSCvrBodd
OL2BW517vFY7HvPLbXnlKgNvJIayOFoGv3hiZkoQQdEEJ4MjR91NhaqrUMMGlbyL
2cXlfZe1qtKGhJI3xDsr+ygCqF/dQ5JaJfZO+vdshCyOHVN3xKsHLnwepNjt+rP8
ZlcqVIaA/SRXahGOHUsWsLiyEjHScjKp/kWgq7PVAwa2evKMRM3djj/KkWd8G0zG
mMr4vO5CaD/kheM=
-----END CERTIFICATE-----
END
    fi
    if ! [ -e $issuerdir/vagrant.key ]; then
        tee $issuerdir/vagrant.key <<END >/dev/null
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC/mUv3Fu7FLnoh
/HxMkZCCQi2vBbNtkf/P39T2Y+7rkS/jLxgIwEWlTRr9Wzzf7Am+MjTL1MCZd2fF
Ac0FiqIQJON8dDOD99aC/YtsqVi2A7/UenORswTVaJyR2VaCBU2+WvhEOHqO1/sM
SSIdFKHA0WVz9Q7XG8CPnhRBrrk8HNPD4m5yfLRMioUahbXggEQf0AFF3IcrAdVj
P6FlYP5nhMgFi/aLNSQxpb/foyPoXrFOssaP+3tO8TaPqcOiDXhdc3itRWfeqGsM
9UE9EvQvOnl8chHnr1SQFjURzjF2Ae+JIGjoQ1Pn+w0ygusNaIH2S4dwawJjhh5j
/W9fUKnXAgMBAAECggEAOpEggHI5IHsZiEQGtt0UIE0ca9DBTTAA00knbv2TLdze
l4JwxVQItgPAyUtXa1dajxIHw3rQONkgFj97rUL4URkFlKhsit16a+YW9Ws6m8C/
pbKcmx/uzVFB8u9Nm0cFwbdLBoeBJyLsMZA1ZlBFNYyMh4qUM7re/Mekh4NiSfY6
eQxxLsMRjCDIvUaeDDJfEFZ2fNYtelqW20zrKTm+sXeQbzFpIIe6wNPjRyH3eSXp
I2FqxGbXEbRjWBcVplRd1NzLMFzXm76jZOpQitSoOpr3b/QIjB1rXl+H8XgfzEm2
9NiWfOY6l4SoatfS3tw1JkkNtRd0PF2mZ+rhUMiHYQKBgQDgBUY6+2FmJ3dSUp+l
tBB3hzV2FqRcuxMJJzgajtA4lN4U/EEAkAwdydZVY2DfA+FMGSOn5fCj2RJsqYQv
ag6sOexTQXpX4npTa5kKG/vgHotkbM/cZWt9GLVr5Nm20vAfPMopRvzkRGYd8iMM
TodImcPtDUzW3/dijtCzz2xNkQKBgQDa8y8HHqxhXJ7mLurwynshejVtJnHOtBGx
vsX6TnvrKP64xvJZB/37ZU9lO6VCdoxEL02Wbjdr15w/jGHZAJk3PGaFXPgiULjh
4Agfzk5IU9w0Ph4Hwij2ICaF0WSpZw2hwA5JRZcNTvgp5njEX71hC+RkD+mKzv4x
v9FIpUXs5wKBgQCaTIe3EHZhukVBeo9jvsaozYRRNf83r9LIty65fCyHDGJ66dSL
4qu1yNPMNIsAkNeZZqdcedBpypYaKhhV4CMDFVJldfAioGfJFY9vmx69m8w++4Og
Nmr22xH6osIiXt/tZB2KmM6PG12KusDRNTWRF/gPSt3mEpV+WQf/EZtzQQKBgAOh
qvMESDmpLp2Ew7LQuPAaNc6kp5iVFgILtv7q1FVXLbpk2lotrsG/sWxta9VJYBQ1
cKUBGPw57EaFjo3p26C16MFnhFoVWqusapYUdunuMiXPrfHU/5bte5YWngPNSMWZ
COOgOtwmpikTwIcJS3vTlasvNGFwA3lRxCffTeSbAoGAcZVHQzL/WzAcYgAXWS8n
ytw7UZ7OK/eJwg0QF58XDIh6mQOwMufjPdqiRT9DA6PRb78Bo6VVUku5INscryN/
/70Y1fjBal06A2/ro0B4wJM5t6cQQFrkLVfhVXuMByAMmffu9rPLFyNVmnHsHKlR
3YtrpSlwHAvDTw+L5AGYnvo=
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

# usage:   cleoapi [get|post|put|delete] [user:pass@][host:port] resource [data]
# returns: the get/post output
#          host:port defaults to localhost:5080
cleoapi() {
    local verb user password protocol host port resource data
    if [ "$1" = "get" -o "$1" = "post" -o "$1" = "put" -o "$1" = "delete" ]; then verb=$(echo $1 | tr 'a-z' 'A-Z'); shift; fi
    if [ ! "${1#*@}" = "$1" ]; then
        host=${1#*@}
        user=${1%%@*}
        port=${host#*:}
        host=${host%%:*}
        password=${user#*:}
        user=${user%%:*}
        shift;
    elif [ ! "${1#*[.:]}" = "$1" ]; then
        host=$1
        shift
    fi
    if [ -z "$user"     ]; then user=administrator ; fi
    if [ -z "$password" ]; then password=Admin     ; fi
    if [ -z "$host"     ]; then host=localhost     ; fi
    if [ -z "$port"     ]; then port=6080          ; fi
    resource=$1
    data=$2
    if [ "$port" = "80" -o "$port" = "5080" ]; then protocol=http; else protocol=https; fi
    if [ -z "$verb" ]; then if [ "$data" ]; then verb=POST; else verb=GET; fi fi
    if [ "$data" ]; then
        echo $data > /tmp/post.$$
        wget --user="$user" --password="$password" --auth-no-challenge --method=$verb --no-check-certificate \
            --header='Content-Type: application/json' --body-file=/tmp/post.$$ -O - -nv $protocol://$host:$port/api/$resource
        rm /tmp/post.$$
    else
        wget --user="$user" --password="$password" --auth-no-challenge --method=$verb --no-check-certificate \
            --header='Content-Type: application/json' -O - -nv $protocol://$host:$port/api/$resource
    fi
}

# returns: nothing, but creates key.{key,req,crt,p8}
#          issuerdir defaults to $HOME

case $1 in
mvnurl)              shift; mvnurl "$@";;
mvnfile)             shift; mvnfile "$@";;
mvndownload)         shift; mvndownload "$@";;
githuburl)           shift; githuburl "$@";;
githubdownload)      shift; githubdownload "$@";;
githubasseturl)      shift; githubasseturl "$@";;
githubassetdownload) shift; githubassetdownload "$@";;
cleorelease)         shift; cleorelease "$@";;
nexusname)           shift; nexusname "$@";;
jre)                 shift; jre "$@";;
cleourl)             shift; cleourl "$@";;
patchurl)            shift; patchurl "$@";;
nexusurl)            shift; nexusurl "$@";;
mysqlurl)            shift; mysqlurl "$@";;
speak)               shift; speak "$@";;
download)            shift; download "$@";;
cleodownload)        shift; cleodownload "$@";;
patchdownload)       shift; patchdownload "$@";;
nexusdownload)       shift; nexusdownload "$@";;
mysqldownload)       shift; mysqldownload "$@";;
issuerfiles)         shift; issuerfiles "$@";;
issue)               shift; issue "$@";;
cleoapi)             shift; cleoapi "$@";;
esac
