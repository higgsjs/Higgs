FROM dlanguage/dmd:2.073.2

COPY . /src/

WORKDIR /src/source

RUN apt-get update \
 && apt-get install -y build-essential python \
 && make all \
 && apt-get auto-remove

ENTRYPOINT ["/src/source/higgs"]
