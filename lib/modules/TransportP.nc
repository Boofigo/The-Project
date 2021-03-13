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
      socket_t fd;
      socket_store_t socket;
      socket_store_t tempsocket;
      uint16_t size;

      if(call SocketsTable.size()<= MAX_NUM_OF_SOCKETS)
      {

         fd = fdw+1;
         dbg(TRANSPORT_CHANNEL,"fd value%d\n", fd);
         socket.fd=fd;
         call SocketsTable.insert(fd, socket);
      }
      else
      {
         dbg(TRANSPORT_CHANNEL, "No Available Socket: return NULL\n");
         fd = NULL;
      }
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