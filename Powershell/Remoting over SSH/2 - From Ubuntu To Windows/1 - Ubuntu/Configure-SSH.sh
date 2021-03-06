PrivateSSHRSAKey=~/.ssh/id_rsa
PublicSSHRSAKey=${PrivateSSHRSAKey}.pub
WindowsUser=CONTOSO\\administrator
WindowsServer=win10.mshome.net
LinuxUser=whoami
Passphrase=""
#Dedicated authorized file per user
AuthorizedKeys=.ssh/authorized_keys
#shared authorized file for administrators
#AuthorizedKeys="%ProgramData%\ssh\administrators_authorized_keys"
sudo apt install xclip -y

rm $PublicSSHRSAKey, $PrivateSSHRSAKey -f

ssh-keygen -f $PrivateSSHRSAKey -t rsa -q -N "$Passphrase"

#For testing the SSH connection
#ssh -o StrictHostKeyChecking=no $WindowsUser@$WindowsServer
scp -o StrictHostKeyChecking=no $PublicSSHRSAKey $WindowsUser@$WindowsServer:${LinuxUser}_rsa.pub
ssh -o StrictHostKeyChecking=no $WindowsUser@$WindowsServer "type ${LinuxUser}_rsa.pub >> $AuthorizedKeys && net stop sshd && net start sshd && del ${LinuxUser}_rsa.pub"

#Copy the line into the clipboard and just paste it in a PowerShell Core host. It should work like a charm :)
 echo "Invoke-Command -ScriptBlock { \"Hello from \$(hostname)\" } -UserName $WindowsUser -HostName $WindowsServer" | xclip -selection clipboard 
pwsh