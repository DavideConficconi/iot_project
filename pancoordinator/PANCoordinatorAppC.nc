#include "utils.h"
#include "printf.h"

#define NEW_PRINTF_SEMANTICS

configuration PANCoordinatorAppC {}

implementation {
	components MainC, PANCoordinatorC as App;

	components new AMSenderC(AM_MY_MSG);
	components new AMReceiverC(AM_MY_MSG);
	components ActiveMessageC;
	components MessageTaskC as SendMessageTaskC;

	components SerialPrintfC;
    components SerialStartC;


	App.Boot -> MainC.Boot;
	App.Receive -> AMReceiverC;
  	App.AMSend -> AMSenderC;
  	App.SplitControl -> ActiveMessageC;
  	App.PacketAcknowledgements -> ActiveMessageC;
    App.Packet -> AMSenderC;
    App.MessageTask -> SendMessageTaskC;
}
