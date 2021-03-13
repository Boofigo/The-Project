#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/TCP_packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"
#include <stdlib.h>
#include <Timer.h>

module TransportP {
   provides interface Transport;

   uses interface Hashmap<socket_store_t> as sMap;
   uses interface List<int> as sList;
   uses interface List<int> as estList;

   uses interface Timer<TMilli> as closeTimer;
   uses interface SimpleSend as TransportSender;
}

implementation {

   socket_store_t socket;  

   event void closeTimer.fired() {
      //if (socket.state == TIME_WAIT) 
      //{
	   //   socket.state = CLOSED;
      //   dbg(TRANSPORT_CHANNEL, "%d IS NOW CLOSED WITH PORT %d\n", TOS_NODE_ID, socket.src.port);
      //   dbg(TRANSPORT_CHANNEL, "CLOSED BABY!!!!\n");
      //}
      call closeTimer.stop();
   }

   command socket_t Transport.socket()
   {
      int x, i;
      int fd = 255;

      dbg(TRANSPORT_CHANNEL, "Reached socket\n");

      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) 
      {
	      if(!call sMap.contains(i)) 
         {
	         socket.flag = 0;
      	   socket.state = CLOSED;

      	   socket->src.port = 0;
	         socket.src.addr = 0;
  	         socket.dest.port = 0;
	         socket.dest.addr = 0;
  	         socket.lastWritten = 0;
   	      socket.lastAck = 0;
  	         socket.lastSent = 0;
     	      for (x = 0; x < SOCKET_BUFFER_SIZE; x++)
            {
               socket.rcvdBuff[x] = 0;
               socket.sendBuff[x] = 0;
            }
            socket.lastRead = 0;
            socket.lastRcvd = 0;
      	   socket.nextExpected = 0;
   	      socket.RTT = 0;
  	         socket.effectiveWindow = 0;
	         break;
	      }
      }

      fd = i;
      call sMap.insert(fd, socket);

      return fd;
   }

   command error_t Transport.bind(socket_t fd, socket_addr_t *addr) 
   {
      dbg(TRANSPORT_CHANNEL, "Binding\n");
      socket = call sMap.get(fd);

      socket.src.port = addr->port;
      socket.src.addr = addr->addr;

      call sMap.insert(fd, socket);

      return SUCCESS;
   }

   command socket_t Transport.accept(socket_t fd)
   {
      // test
   }

   command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)
   {
      // test
   }

   command error_t Transport.receive(pack* package)
   {
      // test
   }

   command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen)
   {
      // test

   }

   command error_t Transport.connect(socket_t fd, socket_addr_t * addr)
   {
      // test

   }

   command error_t Transport.close(socket_t fd)
   {
      // test

   }

   command error_t Transport.release(socket_t fd)
   {
      // test
   }

   command error_t Transport.listen(socket_t fd) 
   {
      dbg(TRANSPORT_CHANNEL, "Listening\n");

      socket = call sMap.get(fd);

      if (socket.state == CLOSED) 
      {
	      socket.state = LISTEN;
	      call sMap.insert(fd, socket);
	      return SUCCESS;
      }
      else
      {
         return FAIL;
      }
	      
   }

   command void Transport.makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length)
   {
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

}