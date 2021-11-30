# arco-on-zfs
***** This is still a work in progress ****
Scripts will install ArcolinuxD with root on ZFS (based on instructions at https://openzfs.github.io/openzfs-docs). After installing the OS it will download the Arcolinux LeftWM install scripts.

System can be installed all on one disk (ie ESP, boot pool and root pool) however ESP can be set to an already existing ESP and /home can be set to a separate disk.

Work still required:
* more robust error checking of user input
* /home support for multiple disks eg mirror, raidz1, etc
* support for persistent swap
* encrypted boot pool
