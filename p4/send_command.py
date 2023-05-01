#!/usr/bin/env python3
import os
import sys
import traceback
import argparse

#The following used from Nik Sultana's implementation for Hangar
def send_command(thrift_port, json, command):
    if not has_api:
        raise Exception("Could not execute commands: Runtime API not present")
    
    services = RuntimeAPI.get_thrift_services('SimplePre')
    services.extend(SimpleSwitchAPI.get_thrift_services())
    standard_client, mc_client, sswitch_client = thrift_connect('localhost', thrift_port, services)

    load_json_config(standard_client, json)

    api = SimpleSwitchAPI('SimplePre', standard_client, mc_client, sswitch_client)

    return api.onecmd(command)

def main():
    parser = argparse.ArgumentParser(description="Send a command to a BMv2 switch instance running in mininet")
    parser.add_argument('json', help="Path to P4 JSON file for the switch instance")
    parser.add_argument('thrift_port', help="Thrift Port for the switch instance")
    parser.add_argument('command', help="The command to send to the switch instance")
    args = parser.parse_args()
    send_command(args.thrift_port, args.json, args.command)

if __name__ == '__main__':
    try:
        from runtime_CLI import thrift_connect, load_json_config, RuntimeAPI
        has_api = True
        from sswitch_CLI import SimpleSwitchAPI
    except Exception as e:
        print("Cannot import RUNTIME_CLI: %s" % traceback.format_exc())
        has_api = False
    main()
