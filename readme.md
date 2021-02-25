# Arbitrar: User Guided API Misuse Detection

This project aims to apply Active Learning on API Misuse detection.
Arbitrar first fetch, compile, and analyze a given codebase, to create a database.
After static analysis, the user will answer simple yes and no questions to guide the search
on API Misuses.

Roughly, this tool provides the following:

1. Data Collection - fetching real-life projects and compile
2. Static Analysis - using symbolic execution to capture execution traces and extract features
3. Learning - use active learning guided by human to detect API Misuses

## How to use

Please refer to the document [doc/how_to_use.md](doc/how_to_use.md).

## Build

### Docker

The Data Collection framework of this project requires Linux/Ubuntu environment and the user needs
to have root access. Therefore it's the best if we can use Docker Image. We prepared the docker
image for you to play with:

```
cd docker/
docker build -f Dockerfile .
docker run -d --name arbitrar-docker
docker exec -it arbitrar-docker bash
```

The default user is `aspire` and the password is `ai4code`.

When you first run the docker container, please be sure to execute the following scripts:

```
# Inside user aspire's home directory
./install-arbitrar.sh
```
