# syntax=docker/dockerfile:1
# =============================================================================
# ROS 2 Jazzy + Gazebo Harmonic + MuJoCo + CUDA/GPU + GUI (rviz2, gazebo, etc.)
# Base OS: Ubuntu 24.04 "Noble" (required for ROS 2 Jazzy)
# =============================================================================

# 12.6.x is a safe, widely-compatible CUDA version. If your host has a very
# recent NVIDIA driver you *can* bump this to a 13.x tag, but 12.6 will work
# with almost any driver from the last ~2 years.
FROM nvidia/cuda:12.6.3-devel-ubuntu24.04

# ---------------------------------------------------------------------------
# 0. Basic environment
# ---------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=Etc/UTC \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all

SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
        locales curl gnupg2 lsb-release software-properties-common \
        ca-certificates sudo && \
    locale-gen en_US en_US.UTF-8 && \
    update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 1. ROS 2 Jazzy
# ---------------------------------------------------------------------------
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
        http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/ros2.list

RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-jazzy-desktop \
        ros-dev-tools \
        python3-colcon-common-extensions \
        python3-rosdep \
        python3-pip \
        python3-venv && \
    rm -rf /var/lib/apt/lists/*

RUN rosdep init || true

# ---------------------------------------------------------------------------
# 2. Gazebo Harmonic + ROS 2 <-> Gazebo bridge
# ---------------------------------------------------------------------------
RUN curl -sSL https://packages.osrfoundation.org/gazebo.gpg \
        -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] \
        http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/gazebo-stable.list

RUN apt-get update && apt-get install -y --no-install-recommends \
        gz-harmonic \
        ros-jazzy-ros-gz && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 3. GUI / OpenGL support (for rviz2, gazebo, mujoco viewer, etc.)
#    Actual GPU access comes from the NVIDIA Container Toolkit on the host
#    (--gpus all / nvidia runtime) combined with NVIDIA_DRIVER_CAPABILITIES
#    above, which includes "graphics" + "display" so GLX/EGL work.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        mesa-utils \
        libgl1 \
        libglx-mesa0 \
        libegl1 \
        libgles2 \
        x11-apps \
        x11-utils \
        xauth && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 4. MuJoCo (Python package)
# ---------------------------------------------------------------------------
RUN pip3 install --no-cache-dir --break-system-packages mujoco

# ---------------------------------------------------------------------------
# 5. Non-root user (matches host UID/GID so mounted volumes aren't root-owned)
# ---------------------------------------------------------------------------
ARG USERNAME=ros
ARG USER_UID=1000
ARG USER_GID=1000

# Ubuntu 24.04 base images ship a default "ubuntu" user/group already
# sitting on UID/GID 1000. Remove whatever's already there before
# creating ours, so this works whether USER_UID/GID is 1000 or something
# else a student's host happens to use.
RUN if getent passwd ${USER_UID} > /dev/null; then \
        userdel -r "$(getent passwd ${USER_UID} | cut -d: -f1)" 2>/dev/null || true; \
    fi && \
    if getent group ${USER_GID} > /dev/null; then \
        groupdel "$(getent group ${USER_GID} | cut -d: -f1)" 2>/dev/null || true; \
    fi && \
    groupadd --gid ${USER_GID} ${USERNAME} && \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
        -s /bin/bash && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# rosdep needs to be updated as the actual user that will use it later,
# but the rosdep database itself is fine to fetch as root at build time.
RUN rosdep update || true

# ---------------------------------------------------------------------------
# 6. Workspace + entrypoint
# ---------------------------------------------------------------------------
RUN mkdir -p /home/${USERNAME}/ros2_ws/src && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Source ROS 2 (and the workspace overlay, if built) in every new shell,
# not just the entrypoint's process. This is what makes plain
# `docker compose exec ros2 bash` shells "just work" without manually
# re-sourcing setup.bash each time.
RUN echo '' >> /home/${USERNAME}/.bashrc && \
    echo '# Auto-source ROS 2' >> /home/${USERNAME}/.bashrc && \
    echo 'source /opt/ros/jazzy/setup.bash' >> /home/${USERNAME}/.bashrc && \
    echo 'if [ -f /home/'${USERNAME}'/ros2_ws/install/setup.bash ]; then' >> /home/${USERNAME}/.bashrc && \
    echo '    source /home/'${USERNAME}'/ros2_ws/install/setup.bash' >> /home/${USERNAME}/.bashrc && \
    echo 'fi' >> /home/${USERNAME}/.bashrc && \
    chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.bashrc

USER ${USERNAME}
WORKDIR /home/${USERNAME}/ros2_ws

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
