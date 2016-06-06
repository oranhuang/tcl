#!/usr/bin/expect --
# uswitchfactory.tcl eb31 none 0418d63163d7 gnimhek-123 /media/disk/keys ttyUSB0 0 192.168.1.14 02081-07 eb31.bin
set boardid [lindex $argv 0]
set mac [lindex $argv 1]
set passphrase [lindex $argv 2]
set keydir [lindex $argv 3]
set dev [lindex $argv 4]
set idx [lindex $argv 5]
set tftpserver [lindex $argv 6]
set bomrev [lindex $argv 7]
set qrcode [lindex $argv 8]
set fwimg "$boardid.bin"
set rsa_key dropbear_rsa_host_key
set dss_key dropbear_dss_host_key
set user "ubnt"
set passwd "ubnt"
set bootloader_prompt "u-boot>"
set cmd_prefix ""
set ubntaddr "67030020"
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

proc string2hex {string} {
    set str_len [string length $string]
    set hex_str ""
    for {set i 0} {$i < $str_len} {incr i} {
        set cur_hex [format %02x [scan [string index $string $i] %c]]
        append hex_str $cur_hex
    }
    return $hex_str
}


if {$qrcode eq ""} {
    log_debug "launched with params: boardid=$boardid; mac=$mac; passphrase=$passphrase; keydir=$keydir; dev=$dev; idx=$idx; tftpserver=$tftpserver; bomrev=13-$bomrev"
} else {
    set qrhex [string2hex $qrcode]
    log_debug "launched with params: boardid=$boardid; mac=$mac; passphrase=$passphrase; keydir=$keydir; dev=$dev; idx=$idx; tftpserver=$tftpserver; bomrev=13-$bomrev; qrcode=$qrcode ; qrhex=$qrhex"
}

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

proc stop_uboot { } {
    global cmd_prefix
    global bootloader_prompt

    #send "any key"
    
    set timeout 15
    expect { 
	"Switching to RD_DATA_DELAY Step" {
        	#log_progress 2 "Waiting for self calibration in u-boot ..."
		set timeout 90
    		expect { 
		    "Hit any key to stop autoboot" {
        		#log_progress 2 "Stopping u-boot ..."
			send "\r"
    		    } timeout {
			error_critical "Device not found!"
		    }
		}
	} "Hit any key to stop autoboot" {
        	#log_progress 2 "Stopping u-boot ..."
		send "\r"
	} timeout {
		error_critical "Device not found!"
        }
  }

    log_debug "Stopping U-boot"

    set timeout 5
    expect timeout {
    } "$bootloader_prompt"
    
    sleep 1 
    send "\r" 
    set timeout 30
    expect timeout {
        error_critical "U-boot prompt not found !"
    } "$bootloader_prompt"

    sleep 1 
    if { $cmd_prefix != "" } { 
      send "$cmd_prefix uappinit \r" 
    } else {
      send "mdk\r"
    }
    set timeout 30
    expect timeout {
        error_critical "U-boot prompt not found !"
    } "$bootloader_prompt"
}

proc setmac {} {
    global cmd_prefix
    global bootloader_prompt
    global mac

    sleep 2
    send "$cmd_prefix usetmac $mac\r"
    set timeout 10
    expect timeout { 
        error_critical "MAC setting failed!" 
    } "Done."
    set timeout 5
    expect timeout { 
    } "$bootloader_prompt"

    set timeout 5
    send "$cmd_prefix usetmac\r"
    expect timeout {
        error_critical "Unable to get MAC !"
    } -re "MAC0: (.{2}\[-:].{2}\[-:].{2}\[-:].{2}\[-:].{2}\[-:].{2})"
    expect timeout {
        error_critical "prompt not found !"
    } "$bootloader_prompt"

    set mac_str $expect_out(1,string)
 
    send "setenv ethaddr $mac_str; saveenv\r"
    set timeout 5
    expect timeout { 
    } "$bootloader_prompt"

    send_user "\r\n * MAC setting succeded *\r\n"
}

proc set_network_env {} {
    global bootloader_prompt
    global tftpserver
    global ip
    set max_loop 3
    set pingable 0

    for { set i 0 } { $i < $max_loop } { incr i } {

        if { $i != 0 } {
            stop_uboot
        }

        sleep 1
        send "setenv ipaddr $ip\r"
        set timeout 15
        expect timeout { 
            error_critical "U-boot prompt not found !" 
        } "$bootloader_prompt"

        sleep 1
        send "setenv serverip $tftpserver\r"
        set timeout 15
        expect timeout { 
            error_critical "U-boot prompt not found !" 
        } "$bootloader_prompt"

        sleep 2
    
        send "ping $tftpserver\r"
        set timeout 25
        expect timeout {
            	error_critical "Unknown response for ping !"
        } -re ".*host $tftpserver (.*) alive"

       	set timeout 15
        send "ping $tftpserver\r"
        expect timeout {
           error_critical "Unknown response for ping !"
        } -re ".*host $tftpserver (.*) alive"

        set alive_str $expect_out(1,string)

        if { [string equal $alive_str "is"] == 1 } {
            set pingable 1
            break
        } else {
            send "re\r"
        }
    }

    if { $pingable != 1 } {
        error_critical "$tftpserver is not reachable !"
    }
}

# For UAPWASP boards. No rootfs, only initramfs 

proc has_initramfs { boardid } {
    global bootloader_prompt
    global UAP_ID
    global UAPLR_ID
    global UAPMINI_ID
    global UAPOUT_ID
    global UAPWASP_ID
    global UAPWASPLR_ID
    global UAPHSR_ID
    global UAPOUT5_ID
    global UAPPRO_ID

    if { [string equal -nocase $boardid $UAPWASP_ID] == 1 
         || [string equal -nocase $boardid $UAPWASPLR_ID] == 1 } {
         return 1
    } else {
        return 0
    }
}


proc has_dual_image { boardid } {
    global bootloader_prompt
    global UAP_ID
    global UAPLR_ID
    global UAPMINI_ID
    global UAPOUT_ID
    global UAPWASP_ID
    global UAPWASPLR_ID
    global UAPHSR_ID
    global UAPOUT5_ID
    global UAPPRO_ID

    if { [string equal -nocase $boardid $UAPPRO_ID] == 1 
         || [string equal -nocase $boardid $UAPHSR_ID] == 1 } {
         return 1
    } else {
        return 0
    }
}

proc update_firmware { boardid } {
    global cmd_prefix
    global bootloader_prompt
    global fwimg
    global ip


    log_debug "Firmware $fwimg\r"

    #start firmware flashing
    sleep 1
    if { $cmd_prefix == "" } { 
       send "urescue -f\r"
   } else {
       send "setenv do_urescue TRUE; urescue -u\r"
   }
    set timeout 10 
        expect timeout { 
        error_critical "Failed to start urescue" 
    } "TFTPServer started. Wating for tftp connection..."

    sleep 2
    send_user "atftp --option \"mode octet\" -p -l /tftpboot/$fwimg $ip"
    exec atftp --option "mode octet" -p -l /tftpboot/$fwimg $ip 2>/dev/null >/dev/null
    
    sleep 2 
    set timeout 60
    if { $cmd_prefix != "" } { 
        sleep 2 
        set timeout 60
        expect timeout { 
            error_critical "U-boot prompt not found !" 
        } "$bootloader_prompt"
        sleep 2
        set timeout 10
        send "$cmd_prefix uwrite -f \r"
    }
    sleep 2 
    set timeout 60
    expect timeout { 
        error_critical "Failed to download firmware !" 
    } "Firmware Version:"
    
    log_progress 65 "Firmware loaded"
    
#    set timeout 120 
#    expect timeout { 
#        error_critical "Failed to flash firmware !"
#    } "Copying 'u-boot' partition. Please wait... :  done"
    
#    log_progress 70 "Flashing firmware..."

    #set timeout 180
    set timeout 300
    expect timeout { 
        error_critical "Failed to flash firmware !"
    } "Copying to 'kernel0' partition. Please wait... :  done."
    
    log_progress 75 "Firmware flashed"

    set timeout 180
    expect timeout { 
        error_critical "Failed to flash firmware !" 
    } "Firmware update complete."
    
    log_progress 90 "Firmware flashed"
}

proc gen_sshkeys {} {
    global rsa_key
    global dss_key
    global idx

    set full_rsa_key /tftpboot/$rsa_key.$idx
    set full_dss_key /tftpboot/$dss_key.$idx
    
    exec rm -f $full_rsa_key
    exec rm -f $full_dss_key

    exec dropbearkey -t rsa -f $full_rsa_key 2>/dev/null >/dev/null
    exec dropbearkey -t dss -f $full_dss_key 2>/dev/null >/dev/null
    
    exec chmod +r $full_rsa_key
    exec chmod +r $full_dss_key
}

proc upload_sshkeys {} {
    global cmd_prefix
    global bootloader_prompt
    global rsa_key
    global dss_key
    global idx

    set dl_addr 0x01000000

    sleep 2
    send "tftpboot $dl_addr $rsa_key.$idx\r"
    set timeout 15
    expect timeout { 
        error_critical "TFTP failed on $rsa_key.$idx!" 
    } "Bytes transferred ="
    set timeout 5
    expect timeout { 
    } "$bootloader_prompt"

    sleep 2
    send "$cmd_prefix usetsshkey \${fileaddr} \${filesize}\r"
    set timeout 15
    expect timeout { 
        error_critical "setsshkey failed on $rsa_key.$idx!" 
    } "Done."
    set timeout 5
    expect timeout { 
    } "$bootloader_prompt"

    sleep 2
    send "tftpboot $dl_addr $dss_key.$idx\r"
    set timeout 15
    expect timeout { 
        error_critical "TFTP failed on $dss_key.$idx!" 
    } "Bytes transferred ="
    set timeout 5
    expect timeout { 
    } "$bootloader_prompt"

    sleep 2
    send "$cmd_prefix usetsshkey \${fileaddr} \${filesize}\r"
    set timeout 15
    expect timeout { 
        error_critical "setsshkey failed on $dss_key.$idx!" 
    } "Done."
    set timeout 5
    expect timeout { 
    } "$bootloader_prompt"
    
    send_user "\r\n * ssh keys uploaded successfully *\r\n"
}

proc run_client { idx eeprom_txt eeprom_bin eeprom_signed passphrase keydir} {
    global qrcode
    log_debug "Connecting to server:"
    
    set outfile [open "/tmp/client$idx.sh" w]
    puts $outfile "#!/bin/sh\n"
    puts $outfile "set -o verbose\n"
    if {$qrcode eq ""} {
        puts $outfile "/usr/local/sbin/client_x86 \$(cat /tftpboot/$eeprom_txt  | sed -r -e \"s~^field=(.*)\$~-i field=\\1 ~g\" | grep -v \"eeprom\" | tr '\\n' ' ') -i field=flash_eeprom,format=binary,pathname=/tftpboot/$eeprom_bin -o field=flash_eeprom,format=binary,pathname=/tftpboot/$eeprom_signed -k $passphrase -o field=registration_id -o field=result -o field=device_id -o field=registration_status_id -o field=registration_status_msg -o field=error_message -x $keydir/ca.pem -y $keydir/key.pem -z $keydir/crt.pem "
    } else {
        set qrhex [string2hex $qrcode]
        puts $outfile "/usr/local/sbin/client_x86 \$(cat /tftpboot/$eeprom_txt  | sed -r -e \"s~^field=(.*)\$~-i field=\\1 ~g\" | grep -v \"eeprom\" | tr '\\n' ' ') -i field=qr_code,format=hex,value=$qrhex -i field=flash_eeprom,format=binary,pathname=/tftpboot/$eeprom_bin -o field=flash_eeprom,format=binary,pathname=/tftpboot/$eeprom_signed -k $passphrase -o field=registration_id -o field=result -o field=device_id -o field=registration_status_id -o field=registration_status_msg -o field=error_message -x $keydir/ca.pem -y $keydir/key.pem -z $keydir/crt.pem "
    }
    close $outfile

    if { [catch "spawn sh /tmp/client$idx.sh" reason] } {
        error_critical "Failed to spawn client: $reason\n"
    }   
    set sid $spawn_id
    log_debug "sid $sid"

    expect -i $sid { 
        eof { log_debug "Done." }
    }
    catch wait result
    set res [lindex $result 3]
    log_debug "Client result $res"
    if { $res != 0 } {
        error_critical "Registration failure : $res\n"
    }   
}

proc do_security {} {
    global passphrase
    global keydir
    global idx
    global tftpserver
    global user
    global passwd
    global dev

    set helper helper_BCM5334x
    set eeprom_bin      e.b.$idx
    set eeprom_txt      e.t.$idx
    set eeprom_tgz      e.$idx.tgz
    set eeprom_signed   e.s.$idx
    set eeprom_check    e.c.$idx
    set e_s_gz          $eeprom_signed.gz
    set e_c_gz          $eeprom_check.gz

    set timeout 120
    # login    
    expect timeout { 
        error_critical "Failed to boot firmware !" 
    } "Please press Enter to activate this console."

    send "\r"
    
    expect "login:" { send "$user\r" } \
        timeout { error_critical "Login failed" }

    expect "Password:" { send "$passwd\r" } \
        timeout { error_critical "Login failed" }
        
    expect timeout { error_critical "Login failed" } "#"

    if { [ catch { exec rm -f /tftpboot/$eeprom_bin } msg ] } {
        puts "$::errorInfo"
    }
    if { [ catch { exec rm -f /tftpboot/$eeprom_txt } msg ] } {
        puts "$::errorInfo"
    }
    if { [ catch { exec rm -f /tftpboot/$eeprom_signed } msg ] } {
        puts "$::errorInfo"
    }
    if { [ catch { exec rm -f /tftpboot/$eeprom_check } msg ] } {
        puts "$::errorInfo"
    }
    if { [ catch { exec rm -f /tftpboot/$eeprom_tgz } msg ] } {
        puts "$::errorInfo"
    }
    if { [ catch { exec rm -f /tftpboot/$e_s_gz } msg ] } {
        puts "$::errorInfo"
    }
    if { [ catch { exec rm -f /tftpboot/$e_c_gz } msg ] } {
        puts "$::errorInfo"
    }
    
    set timeout 20
    send "\[ ! -f /tmp/$eeprom_bin \] || rm /tmp/$eeprom_bin\r"
    expect timeout { error_critical "Command promt not found" } "#" 
    send "\[ ! -f /tmp/$eeprom_txt \] || rm /tmp/$eeprom_txt\r"
    expect timeout { error_critical "Command promt not found" } "#" 
    send "\[ ! -f /tmp/$eeprom_signed \] || rm /tmp/$eeprom_signed\r"
    expect timeout { error_critical "Command promt not found" } "#" 
    send "\[ ! -f /tmp/$eeprom_check \] || rm /tmp/$eeprom_check\r"
    expect timeout { error_critical "Command promt not found" } "#" 
    send "\[ ! -f /tmp/$eeprom_tgz \] || rm /tmp/$eeprom_tgz\r"
    expect timeout { error_critical "Command promt not found" } "#" 
    send "\[ ! -f /tmp/$e_c_gz \] || rm /tmp/$e_c_gz\r"
    expect timeout { error_critical "Command promt not found" } "#" 
    send "\[ ! -f /tmp/$e_s_gz \] || rm /tmp/$e_s_gz\r"
    expect timeout { error_critical "Command promt not found" } "#" 

    cd /tftpboot
    send "cd /tmp\r"
    expect timeout { error_critical "Command promt not found" } "#" 

    send "$helper -q -c product_class=bcmswitch -o"
    send " field=flash_eeprom,format=binary,"
    send "pathname=$eeprom_bin > $eeprom_txt" 
    send "\r"
    expect timeout { error_critical "Command promt not found" } "#" 

    send "tar zcf $eeprom_tgz $eeprom_bin $eeprom_txt\r"
    expect timeout { error_critical "Command promt not found" } "#" 

    log_debug "Downloading files"

    
    sleep 1
    set timeout 200
    send "lsz -e -v -b $eeprom_tgz\r"
    sleep 1
    system rz -v -b -y < /dev/$dev > /dev/$dev
    expect timeout { error_critical "Command promt not found" } "#" 

    set file_size [file size  "/tftpboot/$eeprom_tgz"]
    
    if { $file_size == 0 } then { ; # check for file exist
        error_critical "EEPROM (tgz) download failure"
    } 

    if { [ catch { exec tar zxf $eeprom_tgz } msg ] } {
        puts "$::errorInfo"
    }

    set file_size [file size  "/tftpboot/$eeprom_bin"]
    if { $file_size == 0 } then { ; # check for file exist
        error_critical "EEPROM (bin) download failure"
    } 

    set file_size [file size  "/tftpboot/$eeprom_txt"]
    if { $file_size == 0 } then { ; # check for file exist
        error_critical "EEPROM (txt) download failure"
    } 
    
    run_client $idx $eeprom_txt $eeprom_bin $eeprom_signed $passphrase $keydir
    
    if { [ catch { exec gzip $eeprom_signed } msg ] } {
        puts "$::errorInfo"
    }

    log_debug "Uploading eeprom..."
    
    set timeout 200
    send "lrz -v -b \r"
    sleep 1
    system sz -e -v -b $e_s_gz > /dev/$dev < /dev/$dev
    expect timeout { error_critical "Command promt not found" } "#"

    set timeout 20
    send "gunzip $e_s_gz\r"
    expect timeout { error_critical "Command promt not found" } "#"

    log_debug "File sent."
    
    log_debug "Writing eeprom..."
   
    send "$helper -q -i "
    send "field=flash_eeprom,format=binary,pathname=$eeprom_signed\r"
    expect timeout { error_critical "Command promt not found" } "#" 
    
    send "dd if=/dev/`awk -F: '/EEPROM/{print \$1}' /proc/mtd"
    send " | sed 's~mtd~mtdblock~g'` of=/tmp/$eeprom_check\r"
    expect timeout { error_critical "Command promt not found" } "#" 

    set timeout 20
    send "gzip $eeprom_check\r"
    expect timeout { error_critical "Command promt not found" } "#"

    sleep 1
    set timeout 200
    send "lsz -e -v -b $e_c_gz\r"
    sleep 1
    system rz -v -b -y < /dev/$dev > /dev/$dev
    expect timeout { error_critical "Command promt not found" } "#" 

    set file_size [file size  "/tftpboot/$e_c_gz"]
    
    if { $file_size == 0 } then { ; # check for file exist
        error_critical "EEPROM (tgz) download failure"
    } 

    if { [ catch { exec gunzip $e_c_gz } msg ] } {
        puts "$::errorInfo"
    }

    set file_size [file size  "/tftpboot/$eeprom_check"]
    if { $file_size == 0 } then { ; # check for file exist
        error_critical "EEPROM (bin) download failure"
    } 

    if { [ catch { exec gunzip $e_s_gz } msg ] } {
        puts "$::errorInfo"
    }

    set file_size [file size  "/tftpboot/$eeprom_signed"]
    if { $file_size == 0 } then { ; # check for file exist
        error_critical "EEPROM (bin) download failure"
    } 

    send "reboot\r"
    expect timeout { error_critical "Command promt not found" } "#" 

    send "exit\r"
    
    log_debug "Checking EEPROM..."
    if { [ catch { exec /usr/bin/cmp /tftpboot/$eeprom_signed /tftpboot/$eeprom_check } results ] } {
        #set details [dict get $results -errorcode]
        
        #if {[lindex $details 0] eq "CHILDSTATUS"} {
        #   set status [lindex $details 2]
            error_critical "EEPROM check failed"
        #} else {
        #}
    }
    #log_debug $results 
    log_debug "EEPROM check OK..."

    log_progress 60 "Rebooting"
    
}

proc check_security {} {
    global user
    global passwd
    global qrcode
    
    set timeout 120
    # login    
    expect timeout { 
        error_critical "Failed to boot firmware !" 
    } "Please press Enter to activate this console."

    send "\r"
    
    expect "login:" { send "$user\r" } \
        timeout { error_critical "Login failed" }

    expect "Password:" { send "$passwd\r" } \
        timeout { error_critical "Login failed" }
        
    expect timeout { error_critical "Login failed" } "#"

    # for concurrent access issue on /proc/ubnthal/system.info
    # sleep 3 
    send "grep -c flashSize /proc/ubnthal/system.info\r"
    expect timeout {
        error_critical "Unable to get flashSize!"
    } -re "(\\d+)\r"
    
    set signed [expr $expect_out(1,string) + 0]
    expect timeout { error_critical "Command promt not found" } "#" 

    log_debug "signed: $signed"
    if {$signed ne 1} {
        error_critical "Device Registration check failed!"
    }

    if {$qrcode ne ""} {
        send "grep qrid /proc/ubnthal/system.info\r"
        expect timeout {
            error_critical "Unable to get qrid!"
        } -re "qrid=(.*)\r"
    
        set qrid $expect_out(1,string)
        expect timeout { error_critical "Command promt not found" } "#" 

        log_debug "qrid: $qrid"
        if {$qrid ne $qrcode} {
            error_critical "QR code doesn't match!"
        }

    }

    log_progress 95 "Device Registration check OK..."

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

proc turn_on_console { boardid } {
    global bootloader_prompt

    send "setenv bootargs 'quiet console=ttyS0,115200"
    send " mem=128M@0x0 mem=128M@0x68000000"
    send " mtdparts=spi1.0:768k(u-boot),64k(u-boot-env),64k(shmoo),15360k(kernel0),15424k(kernel1),1024k(cfg),64k(EEPROM)'\r"

    set timeout 15
    expect timeout { 
        error_critical "U-boot prompt not found !" 
    } "$bootloader_prompt"
}

proc check_macaddr { mac } {
    global cmd_prefix
    global bootloader_prompt

    set timeout 20
    send "$cmd_prefix usetmac\r"
    expect timeout {
        error_critical "Unable to get MAC !"
    } -re "MAC0: (.{2}:.{2}:.{2}:.{2}:.{2}:.{2}).*MAC1: (.{2}:.{2}:.{2}:.{2}:.{2}:.{2})"
 
    set mac_str $expect_out(1,string)
    regsub -all {:} $expect_out(1,string) {} mac0_read
    regsub -all {:} $expect_out(2,string) {} mac1_read
    regsub -all {:} $mac {} mac0_write
    set somehex [format %X [expr 0x[string range $mac0_write 1 1] | 0x2]]
    set mac1_write [string replace $mac0_write 1 1 $somehex]

    if { [string equal -nocase $mac0_write $mac0_read] != 1 
         || [string equal -nocase $mac1_write $mac1_read] != 1} {
        error_critical "MAC address doesn't match!"
    }

    set timeout 5
    expect timeout { 
    } "$bootloader_prompt"

}

proc check_booting { boardid } {
    set timeout 120

    expect timeout {
        error_critical "Kernel boot failure !"
    } "Starting kernel"
}

proc handle_uboot { } {
    global cmd_prefix
    global bootloader_prompt
    global fwimg
    global boardid
    global mac
    global ip
    global bomrev

    set timeout 10

    stop_uboot

    # set Board ID
    sleep 2
    send "$cmd_prefix usetbid $boardid\r"
    set timeout 15
    expect timeout { 
        error_critical "usetbid set failed !" 
    } "Done."
    set timeout 5
    expect timeout { 
        error_critical "U-boot prompt not found !" 
    } "$bootloader_prompt"

    # set BOM Revision
    sleep 2
    send "$cmd_prefix usetbrev $bomrev\r"
    set timeout 15
    expect timeout {
        error_critical "usetbrev set failed !" 
    } "Done."
    set timeout 5
    expect timeout { 
        error_critical "U-boot prompt not found !" 
    } "$bootloader_prompt"
    log_progress 10 "Board ID/Revision set"

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

    # erase linux configuration
    sleep 2 
    erase_linux_config $boardid
    log_progress 15 "Configuration erased"

    # set Ethernet mac address
    setmac
    log_progress 20 "MAC set"

    # reboot
    sleep 1
    send "re\r"

    ## RUN 3, upload ssh keys & check IDs
    stop_uboot

    sleep 1 
    send "printenv\r"
    set timeout 15
    expect timeout { 
        error_critical "U-boot prompt not found !" 
    } "$bootloader_prompt"

    sleep 1
    send "saveenv\r"
    set timeout 15
    expect timeout { 
        error_critical "U-boot prompt not found !" 
    } "$bootloader_prompt"
    #log_progress 20 "Environment Variables set"

    sleep 1
    #load_eth_drv
    set_network_env

    # upload ssh keys
    sleep 1
    gen_sshkeys
    upload_sshkeys
    log_progress 25 "ssh keys uploaded"

    set timeout 20
    send "$cmd_prefix usetbid\r"
    expect timeout {
        error_critical "Unable to get Board ID!"
    } -re "Board ID: (.{4})"
    
    set bid_str $expect_out(1,string)
    log_debug "bid_str: $bid_str"

    if { [string equal -nocase $bid_str $boardid] != 1 } {
        error_critical "Board ID doesn't match!"
    }
    set timeout 5
    expect timeout { 
    } "$bootloader_prompt"

    sleep 1
    set timeout 20
    send "$cmd_prefix usetbrev\r"
    expect timeout {
        error_critical "Unable to get BOM Revision!"
    } -re "BOM Rev: (\\d+\\-\\d+)\r"
    
    set brev_str $expect_out(1,string)
    log_debug "brev_str: $brev_str"

    if { [string equal $brev_str $bomrev] != 1 } {
        error_critical "BOM Revision doesn't match!"
    }
    set timeout 5
    expect timeout { 
        error_critical "U-boot prompt not found !" 
    } "$bootloader_prompt"

    sleep 1
    check_macaddr $mac

    log_progress 30 "Board ID/MAC address checked"

    sleep 1
    turn_on_console $boardid

    ## RUN 4, sign flash
    sleep 1
    send "run bootcmd\r"

    check_booting $boardid
    do_security

    ## RUN 3, upload ssh keys & check IDs
    stop_uboot
    #load_eth_drv
    set_network_env
    sleep 1
    update_firmware $boardid

    check_booting $boardid
    check_security

    log_progress 100 "Completed with MAC0: $mac " 

}

proc handle_login { user passwd } {
    set timeout 20
    log_progress 2 "Detected device in login mode"
    send "$user\r"
    log_debug "Sent username..."
    expect "Password:"
    send "$passwd\r"
    log_debug "Sent password..."
    sleep 2
    send "reboot\r"

    main_detector
}

proc find_version { major minor } {
    global cmd_prefix
    global ubntaddr

    log_debug "Major=$major, Minor=$minor"

    if { ([expr $major] == 1 && [expr $minor] >= 0)
	 || ([expr $major] == 80 && [expr $minor] == 0)  } {
       log_debug "ubntapp firmware"
       set cmd_prefix "go ${ubntaddr} " 
    }
} 

proc main_detector { } {
    global bootloader_prompt
    global user
    global passwd

    set timeout 60
    sleep 1
    send \003
    send "\r"

    expect {
	  -re "U-Boot (unifi-feature-us48p.|unifi-feature-unifi.|usw-v|usw-feature-unifi.)(\[.0-9]+)-(.*)" {
            set id $expect_out(2,string)
            regexp "(\[0-9]+)\.?(\[1-9]*)\.?(\[1-9]*)(.*)" $id ignore major minor release rest

            log_debug "major=$major  minor=$minor"

            if { $minor == "" } {
            set minor "0"
            }
            find_version $major $minor
            handle_uboot
        } "$bootloader_prompt" { 
	    send "reset\r"
            main_detector
        } "UBNT login:" { 
            handle_login $user $passwd 
        } "counterfeit login:" { 
            handle_login $user $passwd
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

log_progress 1 "Waiting - PLUG in the device..."
main_detector

