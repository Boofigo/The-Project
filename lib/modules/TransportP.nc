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

   uses interface Hashmap<socket_store_t> as SocketsTable;

}

implementation {

   socket_t fdw;  

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
      socket_store_t temp;
      socket_addr_t temp_addy;
      error_t e;
      bool suc = FALSE;
      uint16_t size = call SocketsTable.size();
      uint8_t i =1;
      if(call SocketsTable.isEmpty())
      {
         return e = FAIL;
      }
      for(i;i<=size;i++)
      {
   
         temp = call SocketsTable.get(i);
         call SocketsTable.remove(i);
         if(temp.fd ==fd&&!suc)
         {
            suc = TRUE;
            temp_addy.port = addr->port;
            temp_addy.addr = addr->addr;
            //temp.src=temp_addy;
         }
         call SocketsTable.insert(i, temp);
      }
   
      if(suc) 
      {
         dbg(TRANSPORT_CHANNEL, "Sucess\n");
         return e = SUCCESS;
      }
      else
      {
         dbg(TRANSPORT_CHANNEL, "Fail\n");
         return e = FAIL;
      }      
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
      socket_store_t temp;
      error_t e;
      uint16_t size = call SocketsTable.size();
      bool suc = FALSE;
      uint8_t i =0;

      if(call SocketsTable.isEmpty())
      {
         return e = FAIL;
      }
      for(i;i<=size;i++)
      {
         temp = call SocketsTable.get(i);
         call SocketsTable.remove(i);
         if(temp.fd ==fd&&!suc)
         {
            suc = TRUE;
            temp.state =LISTEN;
            if(temp.state==LISTEN)
            {
               dbg(TRANSPORT_CHANNEL,"Changed state to Listen!\n");
            }
            call SocketsTable.insert(temp.fd,temp);
         }
      }
      if(suc) 
      {
         return e = SUCCESS;
      }
      else     
      { 
         return e = FAIL;
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