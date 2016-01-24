function setSubValue(uid, subPrice)
{
	if(document.getElementById('attended-' + uid).checked)
	{
		document.getElementById('amount-' + uid).value = subPrice
	}
	else
	{
		document.getElementById('amount-' + uid).value = ""
	}
}

function new_captcha()
{
var xmlhttp;
if (window.XMLHttpRequest)
  {
  // code for IE7+, Firefox, Chrome, Opera, Safari
  xmlhttp=new XMLHttpRequest();
  }
else if (window.ActiveXObject)
  {
  // code for IE6, IE5
  xmlhttp=new ActiveXObject("Microsoft.XMLHTTP");
  }
else
  {
  alert("Your browser does not support AJAX!");
  }
xmlhttp.onreadystatechange=function()
{
if(xmlhttp.readyState==4)
  {
    document.getElementById("captcha-html").innerHTML=xmlhttp.responseText;
  }
}
xmlhttp.open("GET","new_captcha.pl",true);
xmlhttp.send(null);
}

// @(#) $Id: binding.js 560 2005-12-14 21:57:35Z dom $

// Run code when the page loads.  From
// http://simon.incutio.com/archive/2004/05/26/addLoadEvent
// function addLoadEvent(func) {
//   var oldonload = window.onload;
//   if (typeof window.onload != 'function') {
//     window.onload = func;
//   } else {
//     window.onload = function() {
//       oldonload();
//       func();
//     }
//   }
// }
// 
// // Set up functions to run when events occur.
// function installHandlers() {
//   if (!document.getElementById) return;
//   var reload = document.getElementById('captcha-reload');
//   if (reload) {
//       // When the user leaves this element, call the server.
//       reload.onclick = function() {
//           new_captcha();
//           return true;          // Continue with default action.
//       }
//   }
// }
/*
addLoadEvent( installHandlers );*/