#include <core.p4>
#include <v1model.p4>

typedef bit<48> macAddr;
typedef bit<32> ipv4Addr;
typedef bit<16> netPort;
typedef bit<8> ipv4Proto;
typedef bit<32> TEID;
typedef bit<9> switchPort;

#define ETHERTYPE_IPV4 0x0800
#define TCP_PROTOCOL 0x06
#define UDP_PROTOCOL 0x11
#define GTPU_PORT 2152

header eth_h {
    macAddr dst;
    macAddr src;
    bit<16> type;
}

header ipv4_h {
    bit<4>  version;
    bit<4>  ihl;
    bit<6>  dscp;
    bit<2>  ecn;
    bit<16> length;
    bit<16> id;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    ipv4Proto  protocol;
    bit<16> chksum;
    ipv4Addr src;
    ipv4Addr dst;
}
/*
header tcp_h {
    netPort srcPort;
    netPort dstPort;
    bit<32> seq;
    bit<32> ack;
    bit<4>  dataofs;
    bit<4>  reserved;
    bit<8>  flags;
    bit<16> window;
    bit<16> chksum;
    bit<16> urgptr;
} */

header udp_h {
    netPort srcPort;
    netPort dstPort;
    bit<16> length;
    bit<16> chksum;
}

header gtpu_h {
    bit<3> version;
    bit<1> protocol;
    bit<1> reserved;
    bit<1> extension;
    bit<1> sequence;
    bit<1> npdu;
    bit<8> type;
    bit<16> length;
    TEID teid;
}

struct metadata_t {
    /* unused */
}

struct headers_t {
    eth_h   eth;
    ipv4_h  ipv4;
    udp_h   udp;
    gtpu_h gtpu;
    ipv4_h ipv4Inner;
    udp_h udpInner;
}

parser upfParser(packet_in pkt,
                out headers_t hdr,
                inout metadata_t meta,
                inout standard_metadata_t standard_metadata) {
    state start {
        transition parse_eth;
    }

    state parse_eth {
        pkt.extract(hdr.eth);
        transition select(hdr.eth.type) {
            ETHERTYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            UDP_PROTOCOL: parse_udp;
            default: accept;
        }
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition select(hdr.udp.srcPort) {
            GTPU_PORT: parse_gtpu;
            default: accept;
        }
    }

    state parse_gtpu {
        pkt.extract(hdr.gtpu);
        transition parse_ipv4Inner;
    }

    state parse_ipv4Inner {
        pkt.extract(hdr.ipv4Inner);
        transition select(hdr.ipv4Inner.protocol) {
            UDP_PROTOCOL: parse_udpInner;
            default: accept;
        }
    }

    state parse_udpInner {
        pkt.extract(hdr.udpInner);
        transition accept;
    }
}

control NoVerify(inout headers_t hdr, inout metadata_t meta) { apply {} }

control upfIngress(inout headers_t hdr,
                  inout metadata_t meta,
                  inout standard_metadata_t standard_metadata) {
    action drop() {
        mark_to_drop(standard_metadata);
    }

    table is_ulentry {
        key = {
            hdr.eth.dst: exact;
        }
        actions = {
            NoAction;
        }
    }

    table is_dlentry {
        key = {
            hdr.eth.dst: exact;
        }
        actions = {
            NoAction;
        }
    }

    action ulentry_add(switchPort swport, ipv4Addr nwipv4, ipv4Addr ueipv4, 
                       netPort nwport, netPort ueport, ipv4Proto protocol, 
                       macAddr sgi_da, macAddr sgi_sa) {
        //Packet enters from device,
        //Strip tunnel header
        hdr.gtpu.setInvalid();
        hdr.ipv4 = hdr.ipv4Inner;
        hdr.ipv4Inner.setInvalid();
        hdr.udp = hdr.udpInner;
        hdr.udpInner.setInvalid();
        //Push to internet
        hdr.eth.src = sgi_sa;
        hdr.eth.dst = sgi_da;
        standard_metadata.egress_spec = swport;
    }

    table ulentry {
        key = {
            hdr.ipv4Inner.src: exact;
        }
        actions = {
            ulentry_add;
            NoAction;
        }
    }

    action dlentry_add(switchPort swport, ipv4Addr nwipv4, ipv4Addr ueipv4, 
                       netPort nwport, netPort ueport, ipv4Proto protocol, 
                       macAddr s1u_da, macAddr s1u_sa, ipv4Addr enb_ip, 
                       ipv4Addr spgw_s1u_ip, TEID s1u_teid) {
        //Packet enters from internet
        //Add tunnel header
        hdr.gtpu.setValid();
        hdr.gtpu.version = 1;
        hdr.gtpu.protocol = 1;
        hdr.gtpu.reserved = 0;
        hdr.gtpu.extension = 0;
        hdr.gtpu.sequence = 0;
        hdr.gtpu.npdu = 0;
        hdr.gtpu.type = 0xFF;
        hdr.gtpu.length = hdr.ipv4.length;
        hdr.gtpu.teid = s1u_teid;
        //Move current IP data to inner headers
        hdr.ipv4Inner.setValid();
        hdr.ipv4Inner = hdr.ipv4;
        hdr.udpInner.setValid();
        hdr.udpInner = hdr.udp;
        hdr.udp.setInvalid();
        //Set new IP headers
        hdr.ipv4.src = spgw_s1u_ip;
        hdr.ipv4.dst = enb_ip;
        hdr.ipv4.protocol = protocol;
        hdr.udp.setValid();
        hdr.udp.srcPort = GTPU_PORT;
        hdr.udp.dstPort = GTPU_PORT;
        hdr.udp.length = hdr.gtpu.length + 16;
        hdr.udp.chksum = 0;
        hdr.ipv4.length = hdr.udp.length + 20;
        //Push to enb
        hdr.eth.src = s1u_sa;
        hdr.eth.dst = s1u_da;
        standard_metadata.egress_spec = swport;
    }

    table dlentry {
        key = {
            hdr.ipv4.dst: exact;
        }
        actions = {
            dlentry_add;
            NoAction;
        }
    }


    apply {
        if (hdr.eth.isValid()) {
            if (hdr.ipv4.isValid()) {
                if (is_ulentry.apply().hit && ulentry.apply().hit) {
                    return;
                }
                if (is_dlentry.apply().hit && dlentry.apply().hit) {
                    return;
                }
            }
        }
        drop();
    }
}

control NoEgress(inout headers_t hdr, inout metadata_t meta, inout standard_metadata_t standard_metadata) { apply{} }

control upfComputeChecksum(inout headers_t hdr, inout metadata_t meta) {
    apply {
        update_checksum(hdr.ipv4.isValid(),
                        { hdr.ipv4.version,
                          hdr.ipv4.ihl,
                          hdr.ipv4.dscp,
                          hdr.ipv4.ecn,
                          hdr.ipv4.length,
                          hdr.ipv4.id,
                          hdr.ipv4.flags,
                          hdr.ipv4.fragOffset,
                          hdr.ipv4.ttl,
                          hdr.ipv4.protocol,
                          hdr.ipv4.src,
                          hdr.ipv4.dst },
                        hdr.ipv4.chksum,
                        HashAlgorithm.csum16);
    }
}

control upfDeparser(packet_out pkt, in headers_t hdr) {
    apply {
        pkt.emit(hdr.eth);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.udp);
        pkt.emit(hdr.gtpu);
        pkt.emit(hdr.ipv4Inner);
        pkt.emit(hdr.udpInner);
    }
}

V1Switch(upfParser(), NoVerify(), upfIngress(), NoEgress(), upfComputeChecksum(), upfDeparser()) main;
