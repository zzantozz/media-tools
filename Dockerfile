# Really simple docker file, mostly just to bring in ffmpeg so I can run it consistently anywhere.
# Maybe later I'll decide I want to compile in support for other stuff, and this would be handy
# for that.
FROM ubuntu:25.10

ENV TZ=America/Chicago
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && apt-get install -y \
    bc \
    curl \
    git \
    ffmpeg \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

