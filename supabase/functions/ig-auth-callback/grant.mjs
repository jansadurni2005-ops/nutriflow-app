// Meta documents data:[{access_token,user_id,permissions}]; older grants were flat.
export function grantRow(value){
  if(Array.isArray(value?.data)&&value.data.length!==1)return null;
  const row=Array.isArray(value?.data)?value.data[0]:value;
  return typeof row?.access_token==='string'&&row.access_token.length>0?row:null;
}
export function includesMessages(permissions){
  if(permissions==null)return null;
  const values=Array.isArray(permissions)?permissions:typeof permissions==='string'?permissions.split(','):[];
  return values.some(x=>typeof x==='string'&&x.trim()==='instagram_business_manage_messages');
}
