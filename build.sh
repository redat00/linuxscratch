#!/bin/bash

KERNEL_VERSION=6.7.1
BUSYBOX_VERSION=1.36.1
BASH_VERSION=5.2.21
NANO_VERSION=7.2
OPENSSL_VERSION=3.2.0

init_build () {
	mkdir -p initrd src
	cd initrd
		mkdir sys proc dev etc bin
	cd ..
}

build_linux_kernel () {
	# Building the kernel
	KERNEL_MAJOR=$(echo $KERNEL_VERSION | sed 's/\([0-9]*\)[^0-9].*/\1/')
	wget https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz
	tar -xf linux-$KERNEL_VERSION.tar.xz
	cd linux-$KERNEL_VERSION
		make defconfig
		make -j $(nproc) || exit
	cd ..
	cp linux-$KERNEL_VERSION/arch/x86_64/boot/bzImage ../.
}

build_busybox () {
	# Building busybox
	wget https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2
	tar -xf busybox-${BUSYBOX_VERSION}.tar.bz2
	cd busybox-${BUSYBOX_VERSION}
		make defconfig
		sed 's/^.*CONFIG_STATIC[^_].*$/CONFIG_STATIC=y/g' -i .config
		make -j $(nproc) busybox || exit
	cd ..
}

build_bash () {
	# Building bash
	wget https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz
	tar -xzf bash-${BASH_VERSION}.tar.gz
	cd bash-${BASH_VERSION}
		./configure --enable-static-link
		make -j $(nproc)
	cd ..
}

build_nano () {
	# Building nano
	wget https://nano-editor.org/dist/v7/nano-${NANO_VERSION}.tar.xz
	tar -xf nano-${NANO_VERSION}.tar.xz
	cd nano-${NANO_VERSION}
		./configure
		make -j $(nproc)
	cd ..
}

build_openssl () {
	wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
	tar -xzf openssl-${OPENSSL_VERSION}.tar.gz
	cd openssl-${OPENSSL_VERSION}
		./config -static
		make -j $(nproc)
	cd ..
}

configure_network () {
	mkdir network
	cd network
		echo -e "auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp" > interfaces
		mkdir ifup.d if-pre-up.d if-down.d if-post-down.d
	cd ..
}

create_initrd () {
	cd initrd
		
		# Configure bin folder
		cd bin
			# Copy busybox and create symlink for all the tool
			cp ../../src/bash-$BASH_VERSION/bash ./
			cp ../../src/busybox-$BUSYBOX_VERSION/busybox ./
			for prog in $(./busybox --list); do
				ln -s /bin/busybox ./$prog
			done

			# Copy nano
			cp ../../src/nano-${NANO_VERSION}/src/nano ./

			# Copy openssl
			cp ../../src/openssl-${OPENSSL_VERSION}/apps/openssl ./
		cd ..

		# Configure etc folder
		cd etc
			# passwd and shadow file
			echo 'root:x:0:0:root:/root:/bin/bash' > passwd
			echo 'root:$1$D5cv4HSB$f6ORrG9mIq5i1UeHOj72k/:19697:0:99999:7:::' > shadow

			# network interfaces
			configure_network
		cd ..

		# Construct the default init file
		echo '#!/bin/bash' > init
		echo 'mount -t proc proc /proc' >> init
		echo 'mount -t sysfs sysfs /sys' >> init
		echo 'mount -t devtmpfs udev /dev' >> init
		echo '/bin/mdev -s' >> init 
		echo '/bin/bash' >> init
		chmod +x init

		# Make the initrd
		find . | cpio -o -H newc > ../initrd.img
	
	cd ..
}

init_build
cd src/
build_linux_kernel
build_busybox
build_bash
build_nano
build_openssl
cd ../
create_initrd

