#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    //add component for seenPacketList
    components new ListC(pack, 64) as PacketListC;
    Node.SeenPacketList -> PacketListC; //connects seenPacketList with component ListC

    //add component for ListOfNeighbors
    components new ListC(neighbor*, 64) as ListOfNeighborsC;
    Node.ListOfNeighbors -> ListOfNeighborsC;  //connects ListOfNeighbors with component ListOfNeighborsC

    //add component for PoolOfNeighbors
    //components new PoolC(neighbor, 64) as PoolOfNeighborsC;
    //Node.PoolOfNeighbors -> PoolOfNeighborsC;

    //component for Timer
    components new TimerMilliC() as Timer1C;
    Node.Timer1-> Timer1C;

}