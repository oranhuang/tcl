#!/usr/bin/expect --
set erasecal [lindex $argv 0]
set dev [lindex $argv 1]
set idx [lindex $argv 2]
set boardid [lindex $argv 3]
set fwimg [lindex $argv 4]
set tftpserver [lindex $argv 5]
set user "ubnt"
set passwd "ubnt"
set bootloader_prompt "u-boot>"
set cmd_prefix "go \${ubntaddr} "                                               


#
# procedures
#
proc error_critical {msg} {
    log_error $msg
    exit 2
}

proc log_error { msg } {
    set d [clock format [clock seconds] -format {%H:%M:%S}]
    send_user "\r\n * ERROR: $d $msg * * *\r\n"
}

proc log_warn { msg } {
    set d [clock format [clock seconds] -format {%H:%M:%S}]
    send_user "\r\n * WARN: $d $msg *\r\n"
}

proc log_progress { p msg } {
    set d [clock format [clock seconds] -format {%H:%M:%S}]
    send_user "\r\n=== $p $d $msg ===\r\n"
}

proc log_debug { msg } {
    set d [clock format [clock seconds] -format {%H:%M:%S}]
    send_user "\r\nDEBUG: $d $msg\r\n"
}



log_debug "launched with params: erasecal=$erasecal dev=$dev; idx=$idx; boardid=$boardid; fwimg=$fwimg; tftpserver=$tftpserver"

if { $tftpserver == "" } {
    set tftpserver "192.168.1.19"
}

if {![regexp {(\d+)} $idx]} {
        send_user "Invalid index! Defaulting to 0...\r\n"
        set idx 0
}
set ip_end [expr 21 + $idx]
set ip "192.168.1.$ip_end"

#
# PROCEDURES
#

#proc uboot_finish { } {
#    global bootloader_prompt
#
#    log_progress 50 "Restarting..."
#    send "\r"
#    expect "$bootloader_prompt"
#    send "re\r"
#}

proc stop_uboot { {wait_time 30} } {
    global cmd_prefix
    global bootloader_prompt

    log_debug "Stoping U-boot"
    #send "any key"
    
    set timeout $wait_time
    expect  "Hit any key to stop autoboot" { send "\r"} \
    timeout { error_critical "Device not found!" }  

    set timeout 5
    expect timeout {
    } "$bootloader_prompt"
    
    sleep 1 
    send "\r" 
    set timeout 30
    expect timeout {
        error_critical "U-boot prompt not found !"
    } "$bootloader_prompt"

}

proc handle_urescue {} {
    global bootloader_prompt
    global cmd_prefix
    global fwimg
    global ip
    global tftpserver
    global erasecal 

    sleep 1 
    send "$cmd_prefix uappinit\r" 
    set timeout 30
    expect timeout {
        error_critical "U-boot prompt not found !"
    } "$bootloader_prompt"

    # Erase cal only at the end as mdk needs mac address 
    if { [string equal $erasecal "-e"] == 1 } {
        # erase Calibration Data
        sleep 2
        send "$cmd_prefix uclearcal -f -e\r"
        set timeout 20 
        expect timeout { 
            error_critical "Erase calibration data failed !" 
        } "Done."
        set timeout 5
        expect timeout { 
        } "$bootloader_prompt"
        log_progress 30 "Calibration Data erased"
    }

    sleep 1 
    send "setenv serverip $tftpserver; setenv ipaddr $ip \r"
    set timeout 10
    expect timeout {
        error_critical "U-boot prompt not found !"
    } "$bootloader_prompt"

    sleep 1 
    send "urescue -u\r" 
    set timeout 60
    expect timeout {
        error_critical "U-boot prompt not found !"
    } "TFTPServer started. Wating for tftp connection"

    sleep 2
    send_user "atftp --option \"mode octet\" -p -l /tftpboot/$fwimg $ip"
    exec atftp --option "mode octet" -p -l /tftpboot/$fwimg $ip 2>/dev/null >/dev/null

    set timeout 60
    expect timeout {
        error_critical "U-boot prompt not found !"
    } "$bootloader_prompt"

    log_progress 70 "Download complete"

    sleep 1 
    send "$cmd_prefix uwrite -f\r" 
    set timeout 70
    expect timeout {
        error_critical "U-boot prompt not found !"
    } "Firmware Version:"

    set timeout 300
    expect timeout {
        error_critical "Failed to flash firmware !"
    } "Copying to 'kernel0' partition. Please wait... :  done."

    log_progress 80 "Firmware flashed"

    set timeout 180
    expect timeout {
        error_critical "Failed to flash firmware !"
    } "Firmware update complete."

    log_progress 90 "Firmware flashed"

}

proc handle_login { user passwd reboot } {
    set timeout 20
    
    send "$user\r"
    log_debug "Sent username..."
    expect "Password:"
    send "$passwd\r"
    log_debug "Sent password..."
    sleep 2

    if { $reboot == 1 } {
       send "reboot\r"
       handle_uboot 1
   }
}

proc handle_linux {} {
    global user
    global passwd
    global bootloader_prompt
    global tftpserver
    global ip
    set max_loop 3
 
    set timeout 300 
    send "reset\r"

    for { set i 0 } { $i < $max_loop } { incr i } {

        expect timeout {
              error_critical "Linux Boot Failure"
        } "Please press Enter to activate this console"

        log_debug "Booted Linux..."
        set timeout 10
	send "\r"
        expect timeout {
	    error_critical "Linux Boot Failure"
	} "login:"

        log_debug "Got Linux Login prompt..."
	handle_login $user $passwd 0 

	sleep 10
        send "\rifconfig;ping $tftpserver\r"
        set timeout 60
        expect { 
	    "ping: sendto: Network is unreachable" {
            	error_critical "Network Unreachable"
            } timeout {
                  error_critical "No response for ping !"
                  send \003
                  send "reboot\r"
                  continue
            } -re "64 bytes from $tftpserver"
        }

        send \003
        set timeout 2
        expect timeout {
            error_critical "Linux Hung!!"
        } ".*#"
        send "\r"
        set timeout 2
        expect timeout {
            error_critical "Linux Hung!!"
        } ".*#"
	break
    }
}

proc erase_linux_config { boardid } {
    global cmd_prefix
    global bootloader_prompt
    #global UAPPRO_ID

    send "$cmd_prefix uclearcfg\r"
    set timeout 30
    expect timeout { 
        error_critical "Erase Linux configuration data failed !" 
    } "Done."
    set timeout 5
    expect timeout {
        error_critical "U-boot prompt not found !" 
    } "$bootloader_prompt"
}

proc update_firmware { boardid } {
    global tftpserver
    global fwimg
    set max_loop 3

    log_debug "Firmware $fwimg from $tftpserver\r"

    send "\r"
      set timeout 2
      expect timeout {
         error_critical "Linux Hung!!"
      } -re ".*#"

    #start firmware flashing
    sleep 5
    for { set i 0 } { $i < $max_loop } { incr i } {
      send "cd /tmp/; tftp -r$fwimg -lfwupdate.bin -g $tftpserver\r"
       set timeout 60
       expect { 
         "Invalid argument" {
		continue 
	  } timeout { 
		error_critical "Failed to download Firmware" 
	  } -re ".*#"
       }
       break
    }

    log_progress 40 "Firmware downloaded"

    sleep 2
    set timeout 120
    send "syswrapper.sh upgrade2\r"
    expect timeout { 
        error_critical "Failed to download firmware !" 
    } "Restarting system."
    
    log_progress 90 "Firmware flashed"
}

proc handle_uboot { {wait_prompt 0} } {
    global cmd_prefix
    global bootloader_prompt
    global fwimg
    global mac
    global ip
    global boardid
    global erasecal

    if { $wait_prompt == 2 } {
        log_progress 2 "Waiting for self calibration in u-boot ..."
        stop_uboot 90
    }

    if { $wait_prompt == 1 } {
        stop_uboot
    }

    log_progress 5 "Got INTO U-boot"
    
    sleep 1 
    send "$cmd_prefix uappinit\r" 
    set timeout 30
    expect timeout {
        error_critical "U-boot prompt not found !"
    } "$bootloader_prompt"

    # erase uboot-env
    sleep 2
    send "sf probe\r"
    set timeout 20 
    expect timeout { 
        error_critical "Probe serial flash failed !" 
    } "$bootloader_prompt"

    send "sf erase 0xc0000 0x10000\r"
    set timeout 20 
    expect timeout { 
        error_critical "Erase uboot-env failed !" 
    } "$bootloader_prompt"
    log_progress 10 "uboot-env erased"

    # erase linux configuration
    sleep 2 
    erase_linux_config $boardid
    log_progress 20 "Configuration erased"


    handle_linux
    log_progress 40 "Network environment set"

    # Update kernel 0
    update_firmware $boardid

    stop_uboot
    log_progress 60 "Network environment set"
    # Update Kernel 1
    handle_urescue
    log_progress 95 "Urescue complete"

    set timeout 60
    expect timeout {
        error_critical "Device is not responding after restart !" 
    } "Hit any key to stop autoboot"

    set  timeout 60
    expect timeout {
        error_critical "MFG kernel did not boot properly" 
    } "Verifying Checksum ... OK"

    log_progress 100 "Completed" 

}

proc main_detector { } {
    global user
    global passwd
    global bootloader_prompt
    set timeout 30
    sleep 1
    send \003
    send "\r"

    log_progress 1 "Waiting - PLUG in the device..."

    expect { 
	"Switching to RD_DATA_DELAY Step  :  3 (WL = 0)" { 
		handle_uboot 2 
	} "Board Net Initialization Failed" { 
		handle_uboot 1 
	} "Found MDK device" {
		stop_uboot
		handle_urescue 
	} "$bootloader_prompt" {
		 handle_uboot 
	} "UBNT login:" { 
		handle_login $user $passwd  1 
	} "counterfeit login:" { 
		handle_login $user $passwd 1 
	} timeout { 
		error_critical "Device not found!" 
	}
    } 
}


#
# action starts here
#
#set file [open ~/Desktop/version.txt r]
#while {[gets $file buf] != -1} {
#    send_user "FCD version $buf\n\r"
#}
#close $file


spawn -open [open /dev/$dev w+]
stty 115200 < /dev/$dev
stty raw -echo < /dev/$dev

main_detector

