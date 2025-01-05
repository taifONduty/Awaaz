import 'package:awaaz/global/global.dart';
import 'package:awaaz/screens/login_screen.dart';
import 'package:awaaz/screens/gmap_screen.dart';
import 'package:email_validator/email_validator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import 'forgot_password_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
    
  final nameTextEditingController = TextEditingController();
  final emailTextEditingController = TextEditingController();
  final phoneTextEditingController = TextEditingController();
  final addressTextEditingController = TextEditingController();
  final passwordTextEditingController = TextEditingController();
  final confirmTextEditingController = TextEditingController();
  
  bool _passwordVisible = false;
  
  final _formKey = GlobalKey<FormState>();
  
  void _submit() async{
    if(_formKey.currentState!.validate()) {
      await firebaseAuth.createUserWithEmailAndPassword(
          email: emailTextEditingController.text.trim(),
          password: passwordTextEditingController.text.trim()
      ).then((auth) async {
        currentUser = auth.user;

        if (currentUser != null) {
          Map userMap = {
            "id": currentUser!.uid,
            "name": nameTextEditingController.text.trim(),
            "email": emailTextEditingController.text.trim(),
            "address": addressTextEditingController.text.trim(),
            "phone": phoneTextEditingController.text.trim(),
          };
          DatabaseReference userRef = FirebaseDatabase.instance.ref().child("users");
          userRef.child(currentUser!.uid).set(userMap);
        }
        await Fluttertoast.showToast(msg: "Successfully Registered");
        // Navigator.push(
        //     context, MaterialPageRoute(builder: (c) => MainScreen()));
      });
    }
    else{
      Fluttertoast.showToast(msg: "Not all fields are valid");
    }
  }

  @override
  Widget build(BuildContext context) {
    
    bool darkTheme = MediaQuery.of(context).platformBrightness == Brightness.dark;
      
    return GestureDetector(
      onTap: (){
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.all(0),
          children: [
            Column(
              children: [
                Image.asset(darkTheme? 'images/dark_city.png' : 'images/light_city.png'),

                SizedBox(height: 20,),
                Text(
                  'Register',
                  style: TextStyle(
                    color: darkTheme? Colors.amber.shade400 : Colors.blue,
                    fontSize: 25,
                    fontWeight: FontWeight.bold
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(15,20,15,50),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Form(key: _formKey,
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextFormField(
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(50)
                            ],
                            decoration: InputDecoration(
                              hintText: "Name",
                              hintStyle: TextStyle(
                                color: Colors.grey,
                              ),
                              filled: true,
                              fillColor: darkTheme? Colors.black45 : Colors.grey.shade200,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(width: 0, style: BorderStyle.none),
                              ),
                              prefixIcon: Icon(Icons.person, color: darkTheme? Colors.amber.shade400 : Colors.grey,),
                            ),
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (text){
                              if(text==null || text.isEmpty){
                                return "Name can't be empty";
                              }
                              else if(text.length<2){
                                return "Please enter a valid name";
                              }
                              else if(text.length > 50){
                                return "Enter a short name";
                              }
                            },
                            onChanged: (text)=> setState(() {
                              nameTextEditingController.text = text;
                            }),
                          ),
                          SizedBox(height: 15,),


                          TextFormField(
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(50)
                            ],
                            decoration: InputDecoration(
                              hintText: "Email",
                              hintStyle: TextStyle(
                                color: Colors.grey,
                              ),
                              filled: true,
                              fillColor: darkTheme? Colors.black45 : Colors.grey.shade200,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(width: 0, style: BorderStyle.none),
                              ),
                              prefixIcon: Icon(Icons.mail, color: darkTheme? Colors.amber.shade400 : Colors.grey,),
                            ),
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (text){
                              if(text==null || text.isEmpty){
                                return "Email can't be empty";
                              }
                              if(EmailValidator.validate(text)== true){
                                return null;
                              }
                            },
                            onChanged: (text)=> setState(() {
                              emailTextEditingController.text = text;
                            }),
                          ),
                          SizedBox(height: 20,),

                          IntlPhoneField(
                            showCountryFlag: true,
                            dropdownIcon: Icon(Icons.arrow_drop_down,
                            color: darkTheme? Colors.amber.shade400 : Colors.grey,),
                            decoration: InputDecoration(
                              hintText: "Phone number",
                              hintStyle: TextStyle(
                                color: Colors.grey,
                              ),
                              filled: true,
                              fillColor: darkTheme? Colors.black45 : Colors.grey.shade200,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(width: 0, style: BorderStyle.none),
                              ),
                            ),
                            initialCountryCode: 'BD',
                            onChanged: (text)=> setState(() {
                              phoneTextEditingController.text = text.completeNumber;
                            }),
                          ),
                          TextFormField(
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(50)
                            ],
                            decoration: InputDecoration(
                              hintText: "Address",
                              hintStyle: TextStyle(
                                color: Colors.grey,
                              ),
                              filled: true,
                              fillColor: darkTheme? Colors.black45 : Colors.grey.shade200,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(width: 0, style: BorderStyle.none),
                              ),
                              prefixIcon: Icon(Icons.location_on, color: darkTheme? Colors.amber.shade400 : Colors.grey,),
                            ),
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (text){
                              if(text==null || text.isEmpty){
                                return "Address can't be empty";
                              }
                              if(text.length<2){
                                return "Please enter a valid address";
                              }
                            },
                            onChanged: (text)=> setState(() {
                              addressTextEditingController.text = text;
                            }),
                          ),
                          SizedBox(height: 20,),

                          TextFormField(
                            obscureText: !_passwordVisible,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(50)
                            ],
                            decoration: InputDecoration(
                              hintText: "Password",
                              hintStyle: TextStyle(
                                color: Colors.grey,
                              ),
                              filled: true,
                              fillColor: darkTheme? Colors.black45 : Colors.grey.shade200,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(width: 0, style: BorderStyle.none),
                              ),
                              prefixIcon: Icon(Icons.password_rounded, color: darkTheme? Colors.amber.shade400 : Colors.grey,),
                              suffixIcon: IconButton(
                                icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off),
                                color: darkTheme? Colors.amber.shade400 : Colors.grey
                                ,
                                onPressed: (){
                                setState(() {
                                  _passwordVisible = !_passwordVisible;
                                });
                              }, )
                            ),
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (text){
                              if(text==null || text.isEmpty){
                                return "Password can't be empty";
                              }
                              if(text.length<6){
                                return "Please enter a valid password";
                              }
                            },
                            onChanged: (text)=> setState(() {
                              passwordTextEditingController.text = text;
                            }),
                          ),

                          SizedBox(height: 20,),

                          TextFormField(
                            obscureText: !_passwordVisible,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(50)
                            ],
                            decoration: InputDecoration(
                                hintText: "Confirm password",
                                hintStyle: TextStyle(
                                  color: Colors.grey,
                                ),
                                filled: true,
                                fillColor: darkTheme? Colors.black45 : Colors.grey.shade200,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(25),
                                  borderSide: BorderSide(width: 0, style: BorderStyle.none),
                                ),
                                prefixIcon: Icon(Icons.password_rounded, color: darkTheme? Colors.amber.shade400 : Colors.grey,),
                                suffixIcon: IconButton(
                                  icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off),
                                  color: darkTheme? Colors.amber.shade400 : Colors.grey
                                  ,
                                  onPressed: (){
                                    setState(() {
                                      _passwordVisible = !_passwordVisible;
                                    });
                                  }, )
                            ),
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (text){

                              if(text != passwordTextEditingController.text){
                                return "Password doesn't match";
                              }
                            },
                            onChanged: (text)=> setState(() {
                              confirmTextEditingController.text = text;
                            }),
                          ),
                          SizedBox(height: 20,),

                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                            backgroundColor: darkTheme? Colors.amber.shade400 : Colors.blue,
                              foregroundColor: darkTheme? Colors.black : Colors.white,
                            elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),

                              ),
                              minimumSize: Size(double.infinity, 50),
                          ), onPressed: (){
                              _submit();
                          }, child: Text('Register',style: TextStyle(fontSize: 20,
                          ),
                          ),
                          ),
                          SizedBox(height: 20,),
                          GestureDetector(
                            onTap: (){
                              Navigator.push(context, MaterialPageRoute(builder: (c) => ForgotPassword()));

                            },
                            child: Text('Forgot password?',style: TextStyle(color: darkTheme? Colors.amber.shade400: Colors.grey),),

                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Have an account?', style: TextStyle(color:Colors.grey, fontSize: 15),),
                              SizedBox(width: 5,),
                              GestureDetector(
                                onTap: (){
                                  Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen()));

                                },
                                child: Text("Sign in", style: TextStyle(fontSize: 15,color: darkTheme? Colors.amber.shade400: Colors.blue),),

                              )
                            ],
                          )
                        ],
                      ),),
                    ],
                  ),
                )
              ],
            )
          ],
        ),
      ),);
  }
}
