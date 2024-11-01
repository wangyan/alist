appName="alist"
builtAt="$(date +'%F %T %z')"
goVersion=$(go version | sed 's/go version //')
gitAuthor=$(git show -s --format='format:%aN <%ae>' HEAD)
gitCommit=$(git log --pretty=format:"%h" -1)

if [ "$1" = "dev" ]; then
  version="dev"
  webVersion="dev"
else
  version=$(git describe --abbrev=0 --tags)
  webVersion=$(wget -qO- -t1 -T2 "https://api.github.com/repos/wangyan/alist-web-dist/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
fi

echo "backend version: $version"
echo "frontend version: $webVersion"

ldflags="\
-w -s \
-X 'github.com/alist-org/alist/v3/internal/conf.BuiltAt=$builtAt' \
-X 'github.com/alist-org/alist/v3/internal/conf.GoVersion=$goVersion' \
-X 'github.com/alist-org/alist/v3/internal/conf.GitAuthor=$gitAuthor' \
-X 'github.com/alist-org/alist/v3/internal/conf.GitCommit=$gitCommit' \
-X 'github.com/alist-org/alist/v3/internal/conf.Version=$version' \
-X 'github.com/alist-org/alist/v3/internal/conf.WebVersion=$webVersion' \
"

BuildWinArm64() {
  echo building for windows-arm64
  chmod +x ./wrapper/zcc-arm64
  chmod +x ./wrapper/zcxx-arm64
  export GOOS=windows
  export GOARCH=arm64
  export CC=$(pwd)/wrapper/zcc-arm64
  export CXX=$(pwd)/wrapper/zcxx-arm64
  export CGO_ENABLED=1
  go build -o "$1" -ldflags="$ldflags" -tags=jsoniter .
}

FetchWebDev() {
  curl -L https://codeload.github.com/wangyan/alist-web-dist/tar.gz/refs/heads/develop -o alist-web-dist-develop.tar.gz
  tar -zxvf alist-web-dist-develop.tar.gz
  rm -rf public/dist
  mv -f alist-web-dist-develop/dist public
  rm -rf alist-web-dist-develop alist-web-dist-develop.tar.gz
}

FetchWebRelease() {
  curl -L https://github.com/wangyan/alist-web/releases/latest/download/dist.tar.gz -o dist.tar.gz
  tar -zxvf dist.tar.gz
  rm -rf public/dist
  mv -f dist public
  rm -rf dist.tar.gz
}

BuildDev() {
  rm -rf .git/
  mkdir -p "dist"
  muslflags="--extldflags '-static -fpic' $ldflags"
  url="https://musl.nn.ci/x86_64-linux-musl-cross.tgz"
  curl -L -o "x86_64-linux-musl-cross.tgz" "${url}"
  sudo tar xf "x86_64-linux-musl-cross.tgz" --strip-components 1 -C /usr/local
  echo "building for linux-musl-amd64"
  os_arch="linux-musl-amd64"
  cgo_cc="x86_64-linux-musl-gcc"
  export GOOS=${os_arch%%-*}
  export GOARCH=${os_arch##*-}
  export CC=${cgo_cc}
  export CGO_ENABLED=1
  go build -o ./dist/$appName-$os_arch -ldflags="$muslflags" -tags=jsoniter .
  xgo -targets=windows/amd64 -out "$appName" -ldflags="$ldflags" -tags=jsoniter .
  mv alist-* dist
  cd dist
  find . -type f -print0 | xargs -0 md5sum >md5.txt
  cat md5.txt
}

BuildRelease() {
  rm -rf .git/
  mkdir -p "build"
  BuildWinArm64 ./build/alist-windows-arm64.exe
  xgo -targets=windows/amd64,linux/amd64,linux/arm64,darwin/amd64,darwin/arm64 -out "$appName" -ldflags="$ldflags" -tags=jsoniter .
  mv alist-* build
}

MakeRelease() {
  cd build
  mkdir compress
  for i in $(find . -type f -name "$appName-linux-*"); do
    cp "$i" alist
    tar -czvf compress/"$i".tar.gz alist
    rm -f alist
  done
  for i in $(find . -type f -name "$appName-darwin-*"); do
    cp "$i" alist
    tar -czvf compress/"$i".tar.gz alist
    rm -f alist
  done
  for i in $(find . -type f -name "$appName-windows-*"); do
    cp "$i" alist.exe
    zip compress/$(echo $i | sed 's/\.[^.]*$//').zip alist.exe
    rm -f alist.exe
  done
  cd compress
  find . -type f -print0 | xargs -0 md5sum >"$1"
  cat "$1"
  cd ../..
}

if [ "$1" = "dev" ]; then
  FetchWebDev
  BuildDev
elif [ "$1" = "release" ]; then
  FetchWebRelease
  BuildRelease
  MakeRelease "md5.txt"
else
  echo -e "Parameter error"
fi
