5G User Plane Function Modelled in P4
by Alexander Wolosewicz
in coordination with Ashok Sunder Rajan
Based on "A P4-based 5G User Plane Function" by Robert MacDavid, et. al.

Files:
upf.p4: The P4 configuration for the UPF switch
enb.p4: The P4 configuration for the model base stations
final.yml: The topology file to be used for mininet/BMv2 simulation
run.sh: Used to start the mininet/BMv2 simulation
Makefile: Used to build the P4 files into the used JSON files
send_command.py: Helper file for start_upf_controlplane.sh to send commands to the UPF switch via thrift
start_upf_controlplane.sh: Control plane script, configures DL entries so packets from 'sgi' route to UE hosts

These files were built to run and tested using Hangar; setup steps for Hangar are below. However, the P4 files can be compiled using P4C and the resulting JSON files used in any BMv2 setup. The topology requirements are that there are devices on one side of the UPF (representing the internet), the other UPF connections are to eNB switches, and the eNB switches are connected to hosts or other simulated devices for UEs. The initial control plane commands to run are visibile in final.yml under "cmds" for each switch, but they are of the form:
- UPF: table_add uplink ul_entry_add {eNB subnet}&&&{subnet mask} => {outgoing switch port} {outgoing dst MAC} {outgoing src MAC} 0 (only once, targets "internet" gateway)
- eNB: table_add dl_forwarding dl_forward {device TEID} => {device switch port} {device MAC} {eNB MAC} (once per UE connected to eNB)
       table_add ul_forwarding ul_forward {device IPv4} => {upf switch port} {upf MAC} {eNB MAC} {eNB IPv4} {UPF IPv4} {device TEID} (once per UE connected to eNB)
Additionally, start_upf_controlplane.sh must be updated with the path to the UPF JSON and the thrift port the UPF switch is running on.

The following instructions are for installing, compiling, and running on Hangar:
Installing Hangar:
Download hangargames1.tgz here: https://drive.google.com/drive/folders/1-IH7JH1rk_TcSmaxzPCQuK4yneVXT2Tr?usp=sharing
Install vagrant and Oracle VirtualBox
Uncompress hangargames1.tgz to a new directory and navigate there
Run the command `vagrant init 6fb26064-45b0-4943-842f-4371962726c1 hangargames1.box`
Run the command `vagrant up` and wait until it says "default: Warnining: Authentication failure. Retrying..." in a loop, then you can interrupt twice with ctrl-c and run `vagrant ssh`
The default username and password to ssh in are 'vagrant'
Enter ~/Hangar and run `make clean && make`
Run `HANGARGAMES=/home/vagrant/Hangar/ networks/2net/run_2net.sh` and if the following output appears:
```
Running  ping -c 1 192.0.0.2 on h0 -- returned:0
Running  ping -c 1 192.0.0.3 on h0 -- returned:0
Running  ping -c 1 192.0.0.2 on h1 -- returned:0
Running  ping -c 1 192.0.0.3 on h1 -- returned:0
```
Then Hangar is successfully setup.
The files for this setup can be moved into Hangar using scp -P. The default port is 2222.
The files should be placed in the directory ~/Hangar/networks/upf

Compiling:
By default, running 'make' will compile upf.p4 and enb.p4 into their .json forms and place them at ~/Hangar/build/BMv2/networks/upf/, starting from a directory in ~/Hangar/networks/ (so the path used is ../../build/BMV2/networks/upf/). If the intent is to compile the JSON files to another location, that location must be updated in the switch entries in final.yml under 'cfg:' (upf.json for upf and enb.json for enb1 and enb2) and within start_upf_controlplane.sh in the variable JSON_PATH.

Running:
To quickly run a short demonstration, start the UPF control plane in one terminal by running ./start_upf_controlplane and in another terminal start the mininet/BMv2 simulation as normal. A quick note, the UPF control plane assumes the UPF switch is given a thrift port of 9092 - if this is not the case, update the THRIFT_PORT variable in start_upf_controlplane with the correct value. Running run.sh with MODE=selftest will run a test whereby the correct result is

in mininet:
Running  ping -c 1 13.7.1.110 on ue1 -- returned:1
Running  ping -c 1 13.7.1.110 on ue2 -- returned:1
Running  ping -c 1 13.7.1.110 on ue3 -- returned:1
Running  ping -c 1 13.7.1.110 on ue1 -- returned:0
Running  ping -c 1 13.7.1.110 on ue2 -- returned:0
Running  ping -c 1 13.7.1.110 on ue3 -- returned:0
Running  ping -c 1 16.0.0.1 on sgi -- returned:0
Running  ping -c 1 16.0.0.2 on sgi -- returned:0
Running  ping -c 1 16.0.0.3 on sgi -- returned:0
Running  ping -c 4 13.7.1.110 on ue1 -- returned:0
Directly running  sleep 5 -- returned:0

in the control plane terminal:
New UL entry recorded
Added new DL entry for UE with IP 16.0.0.1 as entry 0
UE with IP 16.0.0.1 has used (0 bytes, 0 packets) of data on DL
New UL entry recorded
Added new DL entry for UE with IP 16.0.0.2 as entry 1
UE with IP 16.0.0.2 has used (0 bytes, 0 packets) of data on DL
New UL entry recorded
Added new DL entry for UE with IP 16.0.0.3 as entry 2
UE with IP 16.0.0.3 has used (0 bytes, 0 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.1 has used (294 bytes, 3 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.2 has used (196 bytes, 2 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.3 has used (196 bytes, 2 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.1 has used (490 bytes, 5 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.2 has used (196 bytes, 2 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.3 has used (196 bytes, 2 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.1 has used (588 bytes, 6 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.1 has used (588 bytes, 6 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.1 has used (588 bytes, 6 packets) of data on DL
New UL entry recorded
UE with IP 16.0.0.1 has used (588 bytes, 6 packets) of data on DL

The control plane terminal may have veried numbers for bytes/packets counted on DL, but the final counts should mirror the above (i.e. the last entries should show UE 16.0.0.1 using exactly 6 packets on DL). The first three pings fail because the response is dropped by the UPF before the control plane is able to configure the DL match-action table, but once it is configured all future responses correctly route.
