#!/bin/bash

run_mypy() {
  mypy ./src
  if [[ $? -ne 0 ]]; then
    echo "error: mypy errors, check before comitting"
    return 0
  else
    return 1
  fi
}

run_flake8() {
  flake8 ./src
  if [[ $? -ne 0 ]]; then
    echo "error: flake8 errors, check before comitting"
    return 0
  else
    return 1
  fi
}

run_tester() {
  echo "error: not yet implemented"
  return 1
}

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 [COMMAND]"
  exit
fi

case $1 in
  "check")
    run_mypy
    run_flake8
    ;;
  "test")
    run_tester
    ;;
  "all")
    run_mypy
    run_tester
    ;; 
  *)
    echo "error: unknown command $1"
    ;;
esac
