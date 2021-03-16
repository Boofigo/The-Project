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

   TCPpack sendPackage;

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
      int i;
      int found = 0;
      socket_t fd;
      socket_store_t socket;
      
      for (i = 1; i < MAX_NUM_OF_SOCKETS; i++) 
      {
         if(!call SocketsTable.contains(i)) 
         {
            fd = i;
            dbg(TRANSPORT_CHANNEL,"Socket %d allocated\n", fd);
            call SocketsTable.insert(fd, socket);
            found = 1;
            break;
         }
      }
      if(found == 0)
      {
         dbg(TRANSPORT_CHANNEL, "No Available Socket: return NULL\n");
         fd = NULL;
      }
      return fd;
   }

   command error_t Transport.bind(socket_t fd, socket_addr_t *addr) 
   {
      socket_store_t temp;
      uint8_t i =1;

      if(call SocketsTable.isEmpty())
      {
         dbg(TRANSPORT_CHANNEL, "Fail\n");
         return FAIL;
      }
      for(i;i<=MAX_NUM_OF_SOCKETS;i++)
      {
         if(i == fd)
         {
            temp = call SocketsTable.get(i);
            call SocketsTable.remove(i);

            temp.src = addr->port;

            call SocketsTable.insert(i, temp);
            dbg(TRANSPORT_CHANNEL, "Socket successfully bound\n");
            return  TRUE;     
         }  
      }

      //dbg(TRANSPORT_CHANNEL, "Fail\n");
      return  FAIL;     
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
      uint16_t* message;

      message = [0];

      makePack(&sendPackage, , TOS_NODE_ID, SYN_Flag, 0, message);
      return FAIL;
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
      uint8_t i =0;

      if(call SocketsTable.isEmpty())
      {
         // dbg(TRANSPORT_CHANNEL, "Fail\n");
         return FAIL;
      }
      for(i;i<=MAX_NUM_OF_SOCKETS;i++)
      {
         if(i ==fd)
         {
            temp = call SocketsTable.get(i);
            call SocketsTable.remove(i);

            temp.state =LISTEN;

            dbg(TRANSPORT_CHANNEL,"Changed state to Listen!\n");

            call SocketsTable.insert(i,temp);
            // dbg(TRANSPORT_CHANNEL, "True\n");
            return SUCCESS;
         }
      }

      // dbg(TRANSPORT_CHANNEL, "Fail\n");
      return FAIL;
  
   }

   command void Transport.makePack(TCPpack *Package, uint8_t destport, uint8_t srcport, uint8_t flag, uint8_t seq, uint16_t* payload)
   {
      Package->destport = destport;
      Package->srcport = srcport;
      Package->flag = flag;
      Package->seq = seq;
      memcpy(Package->payload, payload, TCP_PACKET_MAX_PAYLOAD_SIZE);
   }

}