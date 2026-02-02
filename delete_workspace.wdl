version 1.0

workflow Microreact_Delete {
	input {
		File token
		String workspace_uri
	}

	call mr_delete {
		input:
			token = token,
			workspace_uri = workspace_uri
	}
}

task mr_delete {
	input {
		File token
		String workspace_uri
	}
	
	command <<<
		set -eu pipefail
		set +x
		python3 << CODE
		import requests
		import time

		with open("~{token}", 'r', encoding="utf-8") as file:
			TOKEN_STR = file.readline().strip()

		def delete_mr_project(token, mr_url, retries=-1):
			retries += 1
			if retries < 3:
				try:
					# Request info
					print(f"[DEBUG] Attempt {retries + 1}")
					print(f"[DEBUG] URL: https://microreact.org/api/projects/bin/")
					print(f"[DEBUG] Project ID: {mr_url}")
					
					update_resp = requests.post(
						"https://microreact.org/api/projects/bin/",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						params={"project": mr_url},
						timeout=10
					)
					
					# Response info
					print(f"[DEBUG] Status code: {update_resp.status_code}")
					print(f"[DEBUG] Response body: {update_resp.text!r}")
					print(f"[DEBUG] Response headers: {dict(update_resp.headers)}")
					print()
					
					if update_resp.status_code == 200:
						print(f"Deleted {mr_url}")
						return
					else:
						print(f"Failed to delete MR project {mr_url} [code {update_resp.status_code}]: {update_resp.text}")
						delete_mr_project(token, mr_url, retries)
				except Exception as e:
					print(f"Caught exception trying to delete MR project {mr_url}: {e}")
					if retries != 2:
						time.sleep(2)
					else:
						print("SLEEPING FOR A MINUTE...")
						time.sleep(60)
					delete_mr_project(token, mr_url, retries)
			else:
				print(f"Failed to delete MR project {mr_url} after multiple retries. Something's broken.")
				exit(1)

		delete_mr_project(TOKEN_STR, "~{workspace_uri}")

		CODE

	>>>

	runtime {
		cpu: 2
		disks: "local-disk 10 HDD"
		docker: "ashedpotatoes/dropkick:0.0.2"
		memory: "8 GB"
		preemptible: 2
		maxRetries: 1
	}
}
