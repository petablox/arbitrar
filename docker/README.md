# Debloating Docker-Image Builders

## How to Build

(Ziyang, you don't need to do this part)

Usage:
```
docker build -t petablox/ll-analyzer-builder:<TAG> -f <DOCKERFILE>
```

### Pre-defined Tags
| Dockerfile | Tag |
| --- | --- |
| Dockerfile.bionic.x11forwarding | bionic-x11-ssh |

### How to use

(For the time being, I am hosting on my private docker hub, please pull down like)

```
docker pull acanino1/ll-analyzer-builder:bionic-x11-ssh
```

1. Run the docker
Usage:
```
docker run -p <custom-ssh-port>:22 -d --name <container-name> acanino1/ll-analyzer-builder:<TAG>
```

Example: ssh server will be mapped to port 2020 and container-name is my-test
```
docker run -p 2020:22 -d --name my-test acanino1/ll-analyzer-builder:bionic-x11-ssh
```

(Optional) If you want to use your ssh-keys of the host machine for cloning github-repo in the container,
please mount your ~/.ssh to /home/aspire/.ssh.

```
docker run -p 2020:22 -v ~/.ssh:/home/aspire/.ssh -d --name my-test acanino1/debloat-builder:buster-x11-ssh
```

2. Connect the docker-container through ssh with x11-forwarding

From a remote machine (e.g., your laptop or PC)
```
ssh -p 2020 -Y aspire@fir03.seas.upenn.edu
```

From the host machine (e.g., fir03.seas.upenn.edu)
```
ssh -p 2020 aspire@localhost
```

2. Final setup

Once logged in, run the ``install-ll-extractor.sh`` script in /home/aspire using your github credentials.

After that, you will need to update the apt source list so we can build debian source packages. Using `sudo` open up `/etc/apt/sources.list` and uncomment each of the `#deb-src` lines if the original `deb` line is uncommented. After saving, run `sudo apt-get update`.



