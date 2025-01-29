import 'package:awaaz/global/global.dart';
import 'package:awaaz/screens/login_screen.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {

  final emailTextEditingController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  void _submit(){
    firebaseAuth.sendPasswordResetEmail(email: emailTextEditingController.text.trim()).then((value){
      Fluttertoast.showToast(msg: "We have sent you an email to recover password");
    }).onError((error,stackTrace){
      Fluttertoast.showToast(msg: "Error occured: \n ${error.toString()}");
    });
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
                  'Forgot Password',
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
                                return null;
                              },
                              onChanged: (text)=> setState(() {
                                emailTextEditingController.text = text;
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
                            }, child: Text('Send Reset Password Key',style: TextStyle(fontSize: 20,
                            ),
                            ),
                            ),
                            SizedBox(height: 20,),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Already have an account?', style: TextStyle(color:Colors.grey, fontSize: 15),),
                                SizedBox(width: 5,),
                                GestureDetector(
                                  onTap: (){
                                    Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen()));

                                  },
                                  child: Text("Login", style: TextStyle(fontSize: 15,color: darkTheme? Colors.amber.shade400: Colors.blue),),

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
      ),
    );
  }
}
