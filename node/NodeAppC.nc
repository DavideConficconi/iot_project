#include "utils.h"
#include "printf.h"

#define NEW_PRINTF_SEMANTICS


configuration NodeAppC{}

implementation {

    components MainC,NodeC as App;
    components new AMSenderC(AM_MY_MSG);
    components new AMReceiverC(AM_MY_MSG);
    components ActiveMessageC;
    components new FakeSensorC() as TemperatureSensor;
    components new FakeSensorC() as HumiditySensor;
    components new FakeSensorC() as LuminositySensor;
    components new TimerMilliC() as RandomDataTimerC;
    components new TimerMilliC() as TimeOutTimerC;

    //printf components
    components SerialPrintfC;
    components SerialStartC;


    App.Boot -> MainC;
    App.Receive -> AMReceiverC;
    App.AMSend -> AMSenderC;
    App.SplitControl -> ActiveMessageC;
    App.PacketAcknowledgements -> ActiveMessageC;
    App.Packet -> AMSenderC;
    App.TemperatureSensor -> TemperatureSensor;
    App.HumiditySensor -> HumiditySensor;
    App.LuminositySensor -> LuminositySensor;
    App.RandomDataTimer -> RandomDataTimerC;
    App.TimeOutTimer -> TimeOutTimerC;
}
