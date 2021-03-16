#ifndef __TCP_packet_H__
#define __TCP_packet_H__
 
#define Data_Flag 0 // data transfer
#define Data_Ack_Flag 1
#define SYN_Flag 2 // initiate connection
#define SYN_Ack_Flag 3
#define Fin_Flag 4 // finish
#define Fin_Ack_Flag 5
#define Ack_Flag 6 

enum{
	
	TCP_PACKET_MAX_PAYLOAD_SIZE = 20
};

typedef nx_struct TCPpack{
nx_uint8_t destport;
nx_uint8_t srcport;
nx_uint8_t flag;
nx_uint8_t seq;
nx_uint16_t payload[TCP_PACKET_MAX_PAYLOAD_SIZE];
}TCPpack;


#endif