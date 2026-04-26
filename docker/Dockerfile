FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git fakeroot build-essential ncurses-dev xz-utils \
  libssl-dev bc flex libelf-dev bison rsync dwarves devscripts \
  && rm -rf /var/lib/apt/lists/*

# Entry script that creates a user matching the host UID/GID
RUN cat <<'EOF' > /usr/local/bin/entrypoint.sh
#!/bin/bash
set -e

HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}
USER_NAME=builder
GROUP_NAME=builder

# Evict any existing user holding the target UID (must happen before groupdel)
existing=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -n "$existing" ] && [ "$existing" != "$USER_NAME" ]; then
  userdel "$existing"
fi

# Evict any existing group holding the target GID
existing_group=$(getent group "$HOST_GID" | cut -d: -f1)
if [ -n "$existing_group" ] && [ "$existing_group" != "$GROUP_NAME" ]; then
  groupdel "$existing_group"
fi

if ! getent group "$HOST_GID" >/dev/null; then
  groupadd -g "$HOST_GID" "$GROUP_NAME"
fi

if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  useradd -m -u "$HOST_UID" -g "$HOST_GID" -s /bin/bash "$USER_NAME"
fi

exec gosu "$USER_NAME" "$@"
EOF

# gosu is a tiny, correct su replacement for PID 1
RUN apt-get update && apt-get install -y gosu && rm -rf /var/lib/apt/lists/* \
    && chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
