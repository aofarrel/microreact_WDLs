version 1.0

workflow Microreact_Create_Workspace {
	input {
		File token
		File mr_template_json
	}

	call mr_delete {
		input:
			token = token,
			mr_template_json = mr_template_json
	}

	output {
		String new_workspace_uri = mr_delete.new_workspace_uri
	}
}

task mr_delete {
	input {
		File token
		File mr_template_json
	}
	
	command <<<
		set -eu pipefail
		set +x
		python3 << CODE
		import requests
		import time
		import json

		with open("~{token}", 'r', encoding="utf-8") as file:
			TOKEN_STR = file.readline().strip()

		def create_new_mr_project(token, retries=-1): # returns new URL
			retries += 1
			if retries < 3:
				try:
					with open("~{mr_template_json}", "r", encoding="utf-8") as temp_proj_json:
						mr_document = json.load(temp_proj_json)
					response = requests.post("https://microreact.org/api/projects/create",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						params={"access": "private"},
						timeout=120,
						json=mr_document)
					if response.status_code == 200:
						URL = response.json()['id']
						return URL
					print(f"Failed to create new MR project [code {response.status_code}]: {response.text}")
					print("WAITING TWO SECONDS, THEN RETRYING...")
					time.sleep(2)
					create_new_mr_project(token, retries)
				except Exception as e: # ignore: broad-exception-caught
					print(f"Caught exception trying to create new MR project: {e}")
					if retries != 2:
						print("WAITING TWO SECONDS, THEN RETRYING...")
						time.sleep(2)
					else:
						print("WAITING ONE MINUTE, THEN RETRYING...")
						time.sleep(60)
					create_new_mr_project(token, retries)
			else:
				print(f"Failed to create blank MR project after multiple retries. Something's broken.")
				exit(1)
			return None

		uri = create_new_mr_project(TOKEN_STR) # don't keep trying

		with open("uri.txt", "w", encoding="utf-8") as outfile:
			outfile.write(uri)

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

	output {
		String new_workspace_uri = read_string("uri.txt")
	}
}
