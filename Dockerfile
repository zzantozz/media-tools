# Really simple docker file, mostly just to bring in ffmpeg so I can run it consistently anywhere.
# Maybe later I'll decide I want to compile in support for other stuff, and this would be handy
# for that.
FROM ubuntu:25.10

# Install bc because a utility script somewhere needs it - I think frame calculations?
# Install tzdata because otherwise, the tz stuff below doesn't work.
RUN apt-get update && apt-get install -y \
    bc \
    curl \
    git \
    ffmpeg \
    sqlite3 \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

ENV TZ=America/Chicago
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

