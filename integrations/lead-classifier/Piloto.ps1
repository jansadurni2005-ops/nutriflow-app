# Interactive, bounded pilot, only the operator's verified test account. No secrets in command line or on disk.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function PrivateInput([string]$label) {
  $s=Read-Host $label -AsSecureString
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $s.Dispose() }
}
function RunPilot([string]$mode){
  $out=& node pilot.mjs $mode
  if ($LASTEXITCODE -ne 0){throw 'Se detuvo la prueba. No se ha confirmado la operación.'}
  return ($out | ConvertFrom-Json)
}
try {
  Write-Host 'Solo para tu cuenta secundaria de prueba. No abras el chat; comprueba No leídos desde la lista.'
  $env:SN_TEST_HANDLE=Read-Host 'Usuario @ de tu cuenta secundaria'
  $env:SN_TEST_MC_ID=Read-Host 'ID de esa cuenta en Manychat (Contactos)'
  $env:SN_MC_TOKEN=PrivateInput 'Clave de la cuenta Manychat (Ajustes > API, no regenerar)'
  $env:SN_IG_TOKEN=PrivateInput 'Token de prueba de la app de Meta con permiso de mensajes'
  $peer=& node test-contact.mjs
  if ($LASTEXITCODE -ne 0){throw 'Cuenta de prueba no verificada.'}
  $env:SN_TEST_IG_ID=$peer
  $check=RunPilot 'inspect'
  Write-Host 'Contacto e historial verificados por API.'
  $preview=RunPilot 'preview'
  Write-Host ('Resultado: '+$preview.interest+' | Motivo: '+$preview.reason+' | Indicadores: '+($preview.flags -join ', '))
  if ($preview.review){throw 'El modelo solicita revisión. No se ha cambiado la bandeja.'}
  $env:SN_TEST_REVISION=$preview.revision
  if ((Read-Host '¿Has comprobado que es tu cuenta de prueba, figura SIN LEER y ningún flujo reacciona a los campos SN? Escribe SI para crear campos y probar solo en esa cuenta') -cne 'SI'){return}
  $env:SN_TEST_CONFIRM='ONE_TESTER'
  $env:SN_TEST_FIELDS_AUDITED='YES'
  $null=RunPilot 'fields'
  $saved=RunPilot 'stamp'
  Write-Host ('Campo leído de vuelta: '+$saved.stored)
  if ((Read-Host 'Comprueba que sigue SIN LEER, no recibió otro DM y no cambió Abierto/Cerrado. Para probar 10 minutos solo en esta cuenta, escribe VERIFICADO') -cne 'VERIFICADO'){return}
  $env:SN_TEST_UNREAD_PASSED='YES'
  & node pilot.mjs watch-tester
  if ($LASTEXITCODE -ne 0){throw 'Se ha detenido el ensayo automático.'}
} finally {
 foreach($name in 'SN_MC_TOKEN','SN_IG_TOKEN','SN_TEST_MC_ID','SN_TEST_IG_ID','SN_TEST_HANDLE','SN_TEST_REVISION','SN_TEST_CONFIRM','SN_TEST_FIELDS_AUDITED','SN_TEST_UNREAD_PASSED'){
   Remove-Item ('Env:'+ $name) -ErrorAction SilentlyContinue
 }
}
