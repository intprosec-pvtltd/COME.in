import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../core/design.dart';
class FieldSpec {
  const FieldSpec(this.key,
  this.label,
  {
    this.options,
    this.number=false,
    this.secret=false,
    this.required=true,
    this.defaultValue='',
    this.lines=1
  });
  final String key,
  label,
  defaultValue;
  final List<String>? options;
  final bool number,
  secret,
  required;
  final int lines;
} List<FieldSpec> fieldsFor(String kind,
{
  bool editing=false
})=>switch(kind){
  'property'=>const [
    FieldSpec('name',
    'Property name'),
    FieldSpec('city',
    'City'),
    FieldSpec('address',
    'Address',
    lines:2),
    FieldSpec('upi',
    'UPI ID',
    required:false)
  ],
  'room'=>const [
    FieldSpec('name',
    'Room number'),
    FieldSpec('floor',
    'Floor',
    options:[
      'Ground',
      'Floor 1',
      'Floor 2',
      'Floor 3'
    ]),
    FieldSpec('beds',
    'Bed capacity',
    number:true,
    defaultValue:'2')
  ],
  'resident'||'staff'=>[
    const FieldSpec('name',
    'Full name'),
    const FieldSpec('email',
    'Email'),
    const FieldSpec('phone',
    'Phone',
    required:false),
    if(!editing)const FieldSpec('password',
    'Initial password',
    secret:true),
    if(kind=='resident')...const [
      FieldSpec('room',
      'Room number',
      required:false),
      FieldSpec('bed',
      'Bed number',
      number:true,
      defaultValue:'0')
    ]else const FieldSpec('job',
    'Job / assignment')
  ],
  'expense'=>const [
    FieldSpec('description',
    'Description'),
    FieldSpec('category',
    'Category',
    options:[
      'Utilities',
      'Operations',
      'Food',
      'Maintenance',
      'General'
    ]),
    FieldSpec('amount',
    'Amount (₹)',
    number:true),
    FieldSpec('period',
    'Period YYYY-MM')
  ],
  'booking'=>const [
    FieldSpec('name',
    'Enquirer name'),
    FieldSpec('phone',
    'Phone'),
    FieldSpec('room',
    'Preferred room',
    required:false),
    FieldSpec('status',
    'Status',
    options:[
      'Enquiry',
      'Contacted',
      'Closed',
      'Cancelled'
    ])
  ],
  'facility'=>const [
    FieldSpec('title',
    'Title'),
    FieldSpec('details',
    'Details and timing',
    lines:4),
    FieldSpec('category',
    'Facility',
    options:[
      'water',
      'power',
      'wifi',
      'maintenance',
      'other'
    ]),
    FieldSpec('status',
    'Status',
    options:[
      'scheduled',
      'outage',
      'maintenance',
      'restored',
      'normal'
    ])
  ],
  'notice'=>const [
    FieldSpec('title',
    'Title'),
    FieldSpec('body',
    'Announcement',
    lines:5),
    FieldSpec('category',
    'Priority',
    options:[
      'general',
      'important'
    ]),
    FieldSpec('status',
    'Status',
    options:[
      'active',
      'archived'
    ])
  ],
  'meal'=>const [
    FieldSpec('day',
    'Day',
    options:[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ]),
    FieldSpec('breakfast',
    'Breakfast'),
    FieldSpec('lunch',
    'Lunch'),
    FieldSpec('dinner',
    'Dinner')
  ],
  _=>[
  ]
};
class EntityForm extends StatefulWidget {
  const EntityForm({
    super.key,
    required this.kind,
    this.id,
    this.initial=const {
    }
  });
  final String kind;
  final int? id;
  final Map<String,
  dynamic> initial;
  @override State<EntityForm> createState()=>_EntityFormState();
} class _EntityFormState extends State<EntityForm>{
  final form=GlobalKey<FormState>();
  late List<FieldSpec> fields;
  final controls=<String,
  TextEditingController>{
  };
  bool busy=false;
  String? error;
  int property=0;
  @override void initState(){
    super.initState();
    fields=fieldsFor(widget.kind,
    editing:widget.id!=null);
    for(final f in fields){
      controls[
        f.key
      ]=TextEditingController(text:'${widget.initial[f.key]??f.defaultValue}');
      if(f.options!=null&&!f.options!.contains(controls[
        f.key
      ]!.text))controls[
        f.key
      ]!.text=f.options!.first;
    }property=(widget.initial[
      'property_id'
    ] as num?)?.toInt()??0;
  } @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(widget.kind=='expense'&&controls[
      'period'
    ]!.text.isEmpty)controls[
      'period'
    ]!.text=AppScope.of(context).period;
  } @override void dispose(){
    for(final c in controls.values)c.dispose();
    super.dispose();
  } Future<void> save()async{
    if(!form.currentState!.validate())return;
    setState((){
      busy=true;
      error=null;
    });
    final app=AppScope.of(context);
    final payload=<String,
    dynamic>{
      for(final f in fields)f.key:f.number?num.parse(controls[
        f.key
      ]!.text.trim()):controls[
        f.key
      ]!.text.trim()
    };
    if([
      'room',
      'resident',
      'staff',
      'expense',
      'booking'
    ].contains(widget.kind))payload[
      'property_id'
    ]=property;
    if(widget.kind=='notice')payload[
      'important'
    ]=payload[
      'category'
    ]=='important';
    try{
      await app.save(widget.kind,
      payload,
      id:widget.id);
      if(mounted){
        feedback(context,
        'Saved');
        Navigator.pop(context);
      }
    }catch(e){
      if(mounted)setState(()=>error='$e');
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  } @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final properties=app.rows('properties').where((p)=>p[
      'archived'
    ]!=true).toList();
    return PageBody(title:'${widget.id==null?'Add':'Edit'} ${widget.kind}',
    subtitle:'Fields marked * are required.',
    children:[
      Surface(child:Form(key:form,
      child:Column(children:[
        if([
          'room',
          'resident',
          'staff',
          'expense',
          'booking'
        ].contains(widget.kind))... [
          DropdownButtonFormField<int>(isExpanded:true,
          initialValue:properties.any((p)=>p[
            'id'
          ]==property)?property:0,
          decoration:const InputDecoration(labelText:'Property'),
          items:properties.map((p)=>DropdownMenuItem(value:p[
            'id'
          ]as int,
          child:Text('${p['name']}',
          overflow:TextOverflow.ellipsis))).toList(),
          onChanged:(v)=>setState(()=>property=v??0)),
          const SizedBox(height:16)
        ],
        for(final f in fields)Padding(padding:const EdgeInsets.only(bottom:16),
        child:f.options!=null?DropdownButtonFormField<String>(isExpanded:true,
        initialValue:controls[
          f.key
        ]!.text,
        decoration:InputDecoration(labelText:f.label),
        items:f.options!.map((v)=>DropdownMenuItem(value:v,
        child:Text(v))).toList(),
        onChanged:(v)=>controls[
          f.key
        ]!.text=v??''):TextFormField(controller:controls[
          f.key
        ],
        obscureText:f.secret,
        maxLines:f.secret?1:f.lines,
        keyboardType:f.number?const TextInputType.numberWithOptions(decimal:true):f.key=='email'?TextInputType.emailAddress:TextInputType.text,
        decoration:InputDecoration(labelText:'${f.label}${f.required?' *':''}'),
        validator:(v){
          final value=v?.trim()??'';
          if(f.required&&value.isEmpty)return 'Required';
          if(f.number&&num.tryParse(value)==null)return 'Enter a number';
          if(f.key=='beds'&&((int.tryParse(value)??0)<1||(int.tryParse(value)??0)>100))return 'Use a whole number from 1–100';
          if(f.secret&&value.length<8)return 'Use at least 8 characters';
          if(f.key=='email'&&!value.contains('@'))return 'Enter a valid email';
          return null;
        })),
        if(error!=null)Padding(padding:const EdgeInsets.only(bottom:15),
        child:Semantics(liveRegion:true,
        child:Text(error!,
        style:const TextStyle(color:Colors.red,
        fontSize:12)))),
        FilledButton(onPressed:busy?null:save,
        child:Text(busy?'Saving…':'Save changes'))
      ])))
    ]);
  }
}
