-- Generated whitelist from owning mod settings + explicit native layout fields.
return {
  {key="on",type="bool",label="XIV Notify",help="Shows a short fading toast when you loot an item.",default=true},
  {key="seconds",type="int",label="Toast Seconds",help="",default=3,min=1,max=10,step=1},
  {key="scale",type="int",label="Notification Scale",help="",default=100,min=50,max=200,step=10},
  {key="offset_x",type="int",label="Notification Horizontal Offset",help="",default=0,min=-600,max=600,step=10},
  {key="offset_y",type="int",label="Notification Vertical Offset",help="",default=0,min=-300,max=600,step=10},
  {key="party_notices",type="bool",label="Observed Party Join/Leave Notices",help="",default=false},
  {key="invite_reminders",type="bool",label="Recent Invite Reminder",help="Observed party/alliance invites. Actual pending state and responses stay in the native Party menu. Opening that menu from the reminder needs actions; no auto-accept.",default=true},
  {key="request_offset_x",type="int",label="Invite Reminder Horizontal Offset",help="",default=0,min=-800,max=800,step=10},
  {key="request_offset_y",type="int",label="Invite Reminder Vertical Offset",help="",default=0,min=-500,max=500,step=10},
}
