sudo rm /usr/bin/x86_64-linux-gnu-gcc
sudo rm /usr/bin/x86_64-linux-gnu-g++
sudo rm /usr/bin/gcc
sudo rm /usr/bin/g++
sudo ln -s /usr/local/bin/wllvm /usr/bin/x86_64-linux-gnu-gcc
sudo ln -s /usr/local/bin/wllvm++ /usr/bin/x86_64-linux-gnu-g++
sudo ln -s /usr/local/bin/wllvm /usr/bin/gcc
sudo ln -s /usr/local/bin/wllvm++ /usr/bin/g++
