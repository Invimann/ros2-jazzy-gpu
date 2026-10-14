# ROS 2 Jazzy + Gazebo Harmonic + MuJoCo + CUDA/GPU Docker

This is your course-provided container: Ubuntu 24.04 with ROS 2 Jazzy,
Gazebo Harmonic, MuJoCo (Python), NVIDIA GPU access, and GUI support (for
`rviz2`, `gz sim`, etc.) already set up. You shouldn't need to install any
of this yourself — just build and run the container below.

## Prerequisites (one-time, on your machine)

1. Docker + Docker Compose v2 installed.
2. Your NVIDIA driver installed (should already be the case).
3. **NVIDIA Container Toolkit** installed and configured — this is what
   lets the container use your GPU:
   ```bash
   sudo apt-get install -y nvidia-container-toolkit
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```

## Files in this folder

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the image: CUDA base -> ROS 2 Jazzy -> Gazebo Harmonic -> MuJoCo -> GUI libs |
| `docker-compose.yml` | How to *run* the image: GPU flag, X11 mount, workspace mount |
| `entrypoint.sh` | Sources ROS 2 automatically every time the container starts |
| `.env` | Your UID/GID, so files created in the container aren't owned by root |
| `ros2_ws/src` | Your ROS 2 workspace source folder — put your packages here |

> **Note:** make sure the env file in this folder is actually named `.env`
> (with the leading dot). If it downloaded as plain `env`, rename it:
> `mv env .env`. Docker Compose only picks it up automatically with the dot.

## How the pieces fit together (so you're not just copy-pasting blindly)

**GPU access**: The `gpus: all` line in `docker-compose.yml` tells Docker
to use the NVIDIA Container Toolkit runtime, which exposes your GPU
driver and CUDA libraries inside the container. You do **not** install an
NVIDIA driver inside the container — it always uses your host's driver.
`NVIDIA_DRIVER_CAPABILITIES=all` additionally exposes the
`graphics`/`display` capability, which is what lets OpenGL/GLX
applications like `rviz2` and Gazebo actually render using the GPU
instead of falling back to slow software rendering.

**GUI windows (X11 forwarding)**: Linux GUI apps talk to an X11 display
server. Rather than running an X server *inside* the container, we let
the container talk to the X server already running on your desktop:
- We mount `/tmp/.X11-unix` (the X11 socket) into the container.
- We pass through the `DISPLAY` environment variable.
- You tell your X server to accept connections from the container
  (step 1 below) — this is the part people usually forget.

## Running it

### 1. One-time per login session:
```bash
xhost +local:docker
```
This tells your X server to trust connections from local Docker
containers. (Run this again if you reboot or log out/in.)

### 2. Build and start the container:
```bash
docker compose up -d --build
```
The first build takes a while (installing ROS 2, Gazebo, etc.) — grab a
coffee. Later runs are fast since the image is already built.

### 3. Get a shell inside it:
```bash
docker compose exec ros2 bash
```
ROS 2 is sourced automatically in every new shell, so you don't need to
run `source /opt/ros/jazzy/setup.bash` yourself.

### 4. Sanity checks — run these once to confirm everything works:
```bash
# GPU visible?
nvidia-smi

# OpenGL / GUI rendering working? A spinning gear window should pop up.
glxgears

# ROS 2 working?
ros2 topic list

# rviz2 opens a window?
rviz2

# Gazebo Harmonic opens a window?
gz sim -v4

# MuJoCo installed?
python3 -c "import mujoco; print(mujoco.__version__)"
```

If `glxgears` and `rviz2` both open windows on your screen and
`nvidia-smi` shows your GPU, you're good to go for the rest of the
course.

### 5. Quick MuJoCo check (optional, humanoid model):
```bash
mkdir -p ~/mujoco_models && cd ~/mujoco_models
curl -O https://raw.githubusercontent.com/google-deepmind/mujoco/main/model/humanoid/humanoid.xml
python3 -m mujoco.viewer
```
Drag `humanoid.xml` into the viewer window that pops up — you should see
a humanoid ragdoll fall over under gravity. That confirms MuJoCo's GPU
rendering path is working too.

### 6. Stopping it:
```bash
docker compose down
```

## Using the workspace

Anything you put in `./ros2_ws/src` on your machine appears at
`/home/ros/ros2_ws/src` inside the container, and vice versa — so you can
edit code with your normal editor/IDE on your machine and build/run it
inside the container:
```bash
cd ~/ros2_ws
colcon build
source install/setup.bash
```
(You'll need to re-run that `source` line, or open a new shell, after
each `colcon build` so the container picks up your newly built packages.)

## Troubleshooting

- **No GUI windows open at all**: did you run `xhost +local:docker` on
  your machine (not inside the container) before starting the container?
- **`nvidia-smi` fails inside the container**: check the NVIDIA Container
  Toolkit prerequisite above — this is almost always the cause.
- **Files you create in `ros2_ws` show up owned by the wrong user on your
  machine**: check `id -u` and `id -g` on your machine and make sure
  those numbers match `UID`/`GID` in the `.env` file, then rebuild with
  `docker compose up -d --build`.
- **`xhost +local:docker` feels too permissive**: use
  `xhost +si:localuser:$(whoami)` instead — it only trusts your own user
  account rather than all local containers.
