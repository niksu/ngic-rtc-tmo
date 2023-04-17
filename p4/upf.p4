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
#define REG_SIZE 16
#define REG_SHIFT 28 //32 - sqrt(REG_SIZE), bitshfit to use REG_SIZE indices

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
        transition accept;
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
    
    // The registers the controlplane will use to create DL entries on new UL entries
    // Each register is of size REG_SIZE, and the dataplane increments idx by one each time it writes
    // While the controlplane scans the registers constantly for an update, then reads the data
    // A larger REG_SIZE gives more leeway for the controlplane to read the registers before they are overwritten
    register<bit<32>>(REG_SIZE) ctrs_r;
    bit<32> ctr;
    register<ipv4Addr>(REG_SIZE) ue_ips_r;
    register<TEID>(REG_SIZE) ue_teids_r;
    register<switchPort>(REG_SIZE) swports_r;
    register<macAddr>(REG_SIZE) s1u_das_r;
    register<macAddr>(REG_SIZE) s1u_sas_r;
    register<ipv4Addr>(REG_SIZE) enb_ips_r;
    register<ipv4Addr>(REG_SIZE) s1u_ips_r;
    register<bit<32>>(1) idxs_r;
    bit<32> idx;

    action ulentry_add(switchPort egress_port, macAddr sgi_da, macAddr sgi_sa) {
        //Write UE IP and needed DL info to registers
        //Control plane will read and add/modify downlink table entries
        idxs_r.read(idx, 0);
        ctrs_r.read(ctr, idx);
        ctr = ctr + 1;
        ctrs_r.write(idx, ctr);
        ue_ips_r.write(idx, hdr.ipv4Inner.src);
        ue_teids_r.write(idx, hdr.gtpu.teid);
        swports_r.write(idx, standard_metadata.ingress_port);
        s1u_das_r.write(idx, hdr.eth.src);
        s1u_sas_r.write(idx, hdr.eth.dst);
        enb_ips_r.write(idx, hdr.ipv4.src);
        s1u_ips_r.write(idx, hdr.ipv4.dst);
        idx = ((idx + 1) << REG_SHIFT) >> REG_SHIFT;
        idxs_r.write(0, idx);
        //Strip tunnel headers
        hdr.ipv4.setInvalid();
        hdr.udp.setInvalid();
        hdr.gtpu.setInvalid();
        //Push to internet
        hdr.eth.src = sgi_sa;
        hdr.eth.dst = sgi_da;
        standard_metadata.egress_spec = egress_port;
    }

    table uplink {
        key = {
            hdr.ipv4.src: ternary;
        }
        actions = {
            ulentry_add;
            NoAction;
        }
    }

    action dlentry_add(switchPort egress_port, macAddr s1u_da, macAddr s1u_sa,
                       ipv4Addr enb_ip, ipv4Addr spgw_s1u_ip, TEID s1u_teid) {
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
        //Move current IP headers to inside
        hdr.ipv4Inner.setValid();
        hdr.ipv4Inner = hdr.ipv4;
        hdr.udpInner.setValid();
        hdr.udpInner = hdr.udp;
        //Set new IP headers
        hdr.ipv4.src = spgw_s1u_ip;
        hdr.ipv4.dst = enb_ip;
        hdr.ipv4.protocol = UDP_PROTOCOL;
        hdr.udp.setValid();
        hdr.udp.srcPort = GTPU_PORT;
        hdr.udp.dstPort = GTPU_PORT;
        hdr.udp.length = hdr.gtpu.length + 16;
        hdr.udp.chksum = 0;
        hdr.ipv4.length = hdr.udp.length + 20;
        //Push to eNB
        hdr.eth.src = s1u_sa;
        hdr.eth.dst = s1u_da;
        standard_metadata.egress_spec = egress_port;
    }

    table downlink {
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
                if (uplink.apply().hit) {
                    return;
                }
                if (downlink.apply().hit) {
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
        update_checksum(hdr.ipv4Inner.isValid(),
                        { hdr.ipv4Inner.version,
                          hdr.ipv4Inner.ihl,
                          hdr.ipv4Inner.dscp,
                          hdr.ipv4Inner.ecn,
                          hdr.ipv4Inner.length,
                          hdr.ipv4Inner.id,
                          hdr.ipv4Inner.flags,
                          hdr.ipv4Inner.fragOffset,
                          hdr.ipv4Inner.ttl,
                          hdr.ipv4Inner.protocol,
                          hdr.ipv4Inner.src,
                          hdr.ipv4Inner.dst },
                        hdr.ipv4Inner.chksum,
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
