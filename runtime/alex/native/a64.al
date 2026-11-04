

# ---- AArch64 : traduction des appels système x86-64 du runtime et de la stdlib -------------------------
func __rt_a64_syscall(nr: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    if nr == 0:
        return __svc(63, a, b, c)                     # read
    if nr == 1:
        return __svc(64, a, b, c)                     # write
    if nr == 2:
        return __svc(56, -100, a, __rt_a64_oflags(b), c) # open -> openat(AT_FDCWD)
    if nr == 3:
        return __svc(57, a)                           # close
    if nr == 4:
        return __rt_a64_stat(-100, a, b, 0)           # stat -> newfstatat
    if nr == 5:
        return __rt_a64_fstat(a, b)
    if nr == 6:
        return __rt_a64_stat(-100, a, b, 256)         # lstat : AT_SYMLINK_NOFOLLOW
    if nr == 8:
        return __svc(62, a, b, c)                     # lseek
    if nr == 9:
        return __svc(222, a, b, c, d, e, f)           # mmap
    if nr == 10:
        return __svc(226, a, b, c)                    # mprotect
    if nr == 11:
        return __svc(215, a, b)                       # munmap
    if nr == 13:
        return __svc(134, a, b, c, d)                 # rt_sigaction
    if nr == 16:
        return __svc(29, a, b, c)                     # ioctl
    if nr == 21:
        return __svc(48, -100, a, b, 0)               # access -> faccessat
    if nr == 22:
        return __svc(59, a, 0)                        # pipe -> pipe2
    if nr == 32:
        return __svc(23, a)                           # dup
    if nr == 33:                                      # dup2 -> dup3 (dup2(fd, fd) : fd s'il est ouvert)
        if a == b:
            r := __svc(25, a, 1)                      # fcntl(F_GETFD)
            if r < 0:
                return r
            return b
        return __svc(24, a, b, 0)
    if nr == 35:
        return __svc(101, a, b)                       # nanosleep
    if nr == 39:
        return __svc(172)                             # getpid
    if nr == 41:
        return __svc(198, a, b, c)                    # socket
    if nr == 42:
        return __svc(203, a, b, c)                    # connect
    if nr == 43:
        return __svc(202, a, b, c)                    # accept
    if nr == 44:
        return __svc(206, a, b, c, d, e, f)           # sendto
    if nr == 45:
        return __svc(207, a, b, c, d, e, f)           # recvfrom
    if nr == 49:
        return __svc(200, a, b, c)                    # bind
    if nr == 50:
        return __svc(201, a, b)                       # listen
    if nr == 52:
        return __svc(205, a, b, c)                    # getpeername
    if nr == 57:
        return __svc(220, 17, 0, 0, 0, 0)             # fork -> clone(SIGCHLD)
    if nr == 59:
        return __svc(221, a, b, c)                    # execve
    if nr == 60:
        return __svc(93, a)                           # exit
    if nr == 61:
        return __svc(260, a, b, c, d)                 # wait4
    if nr == 62:
        return __svc(129, a, b)                       # kill
    if nr == 63:
        return __svc(160, a)                          # uname
    if nr == 72:
        return __svc(25, a, b, c)                     # fcntl
    if nr == 76:
        return __svc(45, a, b)                        # truncate
    if nr == 77:
        return __svc(46, a, b)                        # ftruncate
    if nr == 79:
        return __svc(17, a, b)                        # getcwd
    if nr == 80:
        return __svc(49, a)                           # chdir
    if nr == 82:
        return __svc(38, -100, a, -100, b)            # rename -> renameat
    if nr == 83:
        return __svc(34, -100, a, b)                  # mkdir -> mkdirat
    if nr == 84:
        return __svc(35, -100, a, 512)                # rmdir -> unlinkat(AT_REMOVEDIR)
    if nr == 86:
        return __svc(37, -100, a, -100, b, 0)         # link -> linkat
    if nr == 87:
        return __svc(35, -100, a, 0)                  # unlink -> unlinkat
    if nr == 88:
        return __svc(36, a, -100, b)                  # symlink -> symlinkat
    if nr == 89:
        return __svc(78, -100, a, b, c)               # readlink -> readlinkat
    if nr == 90:
        return __svc(53, -100, a, b)                  # chmod -> fchmodat
    if nr == 92:
        return __svc(54, -100, a, b, c, 0)            # chown -> fchownat
    if nr == 95:
        return __svc(166, a)                          # umask
    if nr == 97:
        return __svc(163, a, b)                       # getrlimit
    if nr == 102:
        return __svc(174)                             # getuid
    if nr == 104:
        return __svc(176)                             # getgid
    if nr == 105:
        return __svc(146, a)                          # setuid
    if nr == 106:
        return __svc(144, a)                          # setgid
    if nr == 107:
        return __svc(175)                             # geteuid
    if nr == 108:
        return __svc(177)                             # getegid
    if nr == 109:
        return __svc(154, a, b)                       # setpgid
    if nr == 110:
        return __svc(173)                             # getppid
    if nr == 111:
        return __svc(155, 0)                          # getpgrp -> getpgid(0)
    if nr == 115:
        return __svc(158, a, b)                       # getgroups
    if nr == 116:
        return __svc(159, a, b)                       # setgroups
    if nr == 117:
        return __svc(147, a, b, c)                    # setresuid
    if nr == 118:
        return __svc(148, a, b, c)                    # getresuid
    if nr == 119:
        return __svc(149, a, b, c)                    # setresgid
    if nr == 120:
        return __svc(150, a, b, c)                    # getresgid
    if nr == 121:
        return __svc(155, a)                          # getpgid
    if nr == 160:
        return __svc(164, a, b)                       # setrlimit
    if nr == 162:
        return __svc(81)                              # sync
    if nr == 169:
        return __svc(142, a, b, c, d)                 # reboot
    if nr == 201:                                     # time -> clock_gettime(CLOCK_REALTIME)
        ts := __alloc_raw(16)
        r := __svc(113, 0, ts)
        if r < 0:
            return r
        if a != 0:
            __store64(a, __load64(ts))
        return __load64(ts)
    if nr == 217:
        return __svc(61, a, b, c)                     # getdents64
    if nr == 7:                                       # poll -> ppoll (délai en millisecondes)
        if c < 0:
            return __svc(73, a, b, 0, 0, 8)
        ts := __alloc_raw(16)
        __store64(ts, c // 1000)
        __store64(ts + 8, (c % 1000) * 1000000)
        return __svc(73, a, b, ts, 0, 8)
    if nr == 133:
        return __svc(33, -100, a, b, c)               # mknod -> mknodat
    if nr == 293:
        return __svc(59, a, b)                        # pipe2
    if nr == 294:
        return __svc(26, a)                           # inotify_init1
    if nr == 254:
        return __svc(27, a, b, c)                     # inotify_add_watch
    if nr == 255:
        return __svc(28, a, b)                        # inotify_rm_watch
    if nr == 48:
        return __svc(210, a, b)                       # shutdown
    if nr == 51:
        return __svc(204, a, b, c)                    # getsockname
    if nr == 53:
        return __svc(199, a, b, c, d)                 # socketpair
    if nr == 54:
        return __svc(208, a, b, c, d, e)              # setsockopt
    if nr == 55:
        return __svc(209, a, b, c, d, e)              # getsockopt
    if nr == 288:
        return __svc(242, a, b, c, d)                 # accept4
    if nr == 240:
        return __svc(180, a, b, c, d)                 # mq_open
    if nr == 241:
        return __svc(181, a)                          # mq_unlink
    if nr == 242:
        return __svc(182, a, b, c, d, e)              # mq_timedsend
    if nr == 243:
        return __svc(183, a, b, c, d, e)              # mq_timedreceive
    if nr == 245:
        return __svc(185, a, b, c)                    # mq_getsetattr
    if nr == 157:
        return __svc(167, a, b, c, d, e)              # prctl
    if nr == 14:
        return __svc(135, a, b, c, d)                 # rt_sigprocmask
    if nr == 289:
        return __svc(74, a, b, c, d)                  # signalfd4
    if nr == 137:
        return __svc(43, a, b)                        # statfs
    if nr == 149:
        return __svc(228, a, b)                       # mlock
    if nr == 150:
        return __svc(229, a, b)                       # munlock
    if nr == 28:
        return __svc(233, a, b, c)                    # madvise
    if nr == 27:
        return __svc(232, a, b, c)                    # mincore
    if nr == 26:
        return __svc(227, a, b, c)                    # msync
    if nr == 202:
        return __svc(98, a, b, c, d, e, f)            # futex
    if nr == 24:
        return __svc(124)                             # sched_yield
    if nr == 99:
        return __svc(179, a)                          # sysinfo
    if nr == 204:
        return __svc(123, a, b, c)                    # sched_getaffinity
    if nr == 280:
        return __svc(88, a, b, c, d)                  # utimensat
    if nr == 228:
        return __svc(113, a, b)                       # clock_gettime
    if nr == 230:
        return __svc(115, a, b, c, d)                 # clock_nanosleep
    if nr == 231:
        return __svc(94, a)                           # exit_group
    if nr == 318:
        return __svc(278, a, b, c)                    # getrandom
    return -38                                        # ENOSYS

# Drapeaux d'open x86-64 -> AArch64 : O_DIRECTORY 0200000 -> 040000, O_NOFOLLOW 0400000 -> 0100000,
# O_LARGEFILE 0100000 -> 0400000 (les autres sont communs).
func __rt_a64_oflags(f: int) -> int:
    r := f & ~(65536 | 131072 | 32768)
    if (f & 65536) != 0:
        r = r | 16384
    if (f & 131072) != 0:
        r = r | 32768
    if (f & 32768) != 0:
        r = r | 131072
    return r

# struct stat d'AArch64 (asm-generic, 128 octets) -> disposition x86-64 (144 octets) attendue par la stdlib.
func __rt_a64_stat(dirfd: int, path: int, out: int, flags: int) -> int:
    g := __alloc_raw(128)
    r := __svc(79, dirfd, path, g, flags)
    if r == 0:
        __rt_a64_stat_copy(g, out)
    return r

func __rt_a64_fstat(fd: int, out: int) -> int:
    g := __alloc_raw(128)
    r := __svc(80, fd, g)
    if r == 0:
        __rt_a64_stat_copy(g, out)
    return r

func __rt_a64_stat_copy(g: int, out: int):
    __zero(out, 144)
    __store64(out, __load64(g))                  # st_dev
    __store64(out + 8, __load64(g + 8))          # st_ino
    __store64(out + 16, __load32(g + 20))        # st_nlink
    __store32(out + 24, __load32(g + 16))        # st_mode
    __store32(out + 28, __load32(g + 24))        # st_uid
    __store32(out + 32, __load32(g + 28))        # st_gid
    __store64(out + 40, __load64(g + 32))        # st_rdev
    __store64(out + 48, __load64(g + 48))        # st_size
    __store64(out + 56, __load32(g + 56))        # st_blksize
    __store64(out + 64, __load64(g + 64))        # st_blocks
    __copy(out + 72, g + 72, 48)                 # st_atime .. st_ctime_nsec (même disposition)
