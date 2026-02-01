# Really simple docker file, mostly just to bring in ffmpeg so I can run it consistently anywhere.
# Maybe later I'll decide I want to compile in support for other stuff, and this would be handy
# for that.
FROM ubuntu:25.10

RUN apt-get update && apt-get install -y \
    curl \
    git \
    ffmpeg \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

