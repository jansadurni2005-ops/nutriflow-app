// Meta documents data:[{access_token,user_id,permissions}]; older grants were flat.
export function grantRow(value){
  if(Array.isArray(value?.data)&&value.data.length!==1)return null;
  const row=Array.isArray(value?.data)?value.data[0]:value;
  return typeof row?.access_token==='string'&&row.access_token.length>0?row:null;
}
export function hasScope(permissions,scope){
  if(permissions==null)return null;
  const values=Array.isArray(permissions)?permissions:typeof permissions==='string'?permissions.split(','):[];
  return values.some(x=>typeof x==='string'&&x.trim()===scope);
}

export const includesMessages=p=>hasScope(p,'instagram_business_manage_messages');
// Persist only a stable category and numeric codes; provider messages can contain credentials.
export function exchangeIssue(http,error){
 const code=Number(error?.code),msg=typeof error?.message==='string'?error.message.toLowerCase():'';
 if(code===200||code===10||(code>=201&&code<=299)){
  if(/tester|test user|developer role|admin role|role on the app/.test(msg))return 'rol_app';
  if(/instagram_business_basic/.test(msg))return 'permiso_basico';
  if(/instagram_business_manage_messages/.test(msg))return 'permiso_mensajes';
  return 'permisos_meta';
 }
 if(code===190)return 'autorizacion_caducada';
 return 'duracion';
}
