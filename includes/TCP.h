#ifndef TCPPACK_H
#define TCPPACK_H

//FLAGS
enum {
	TCP_SYN = 0,
	TCP_ACK = 1,
	TCP_SYNACK = 2,
	TCP_FIN = 3,
	TCP_FINACK = 4,
	TCP_DATA = 5,
	TCP_DATAACK = 6
};

//PAYLOAD SIZES
enum {
	TCP_HEADER_SIZE = 8,
	TCP_MAX_PAYLOAD_SIZE = 28 - TCP_HEADER_SIZE	//28 OR 20??
};

//TCP Packet
typedef nx_struct tcpPack{
	nx_uint8_t srcPort;
	nx_uint8_t destPort;
	nx_uint16_t seq;
	nx_uint8_t ack;
	nx_uint8_t flag;
	nx_uint16_t adWindow;
        nx_uint8_t payload[TCP_MAX_PAYLOAD_SIZE];
}tcpPack;

#endif