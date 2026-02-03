version 1.0

workflow Microreact_Delete {
	input {
		File token
		String workspace_uri
		Boolean verbose        = true
		Int max_python_retries = 0
		Int max_wdl_retries    = 0
	}

	call mr_delete {
		input:
			token = token,
			workspace_uri = workspace_uri,
			verbose = verbose,
			max_python_retries = max_python_retries,
			max_wdl_retries = max_wdl_retries
	}
}

task mr_delete {
	input {
		File token
		String workspace_uri
		Boolean verbose
		Int max_python_retries
		Int max_wdl_retries
	}
	
	command <<<
		set -eu pipefail
		set +x
		python3 << CODE
		import requests
		import time
		import json

		# https://github.com/openwdl/wdl/blob/legacy/versions/1.0/SPEC.md#true-and-false
		verbose = bool(~{true='True' false='False' verbose})
		assert type(verbose) == bool

		with open("~{token}", 'r', encoding="utf-8") as file:
			TOKEN_STR = file.readline().strip()

		def debug_print(response):
			print(f"[DEBUG] Status code: {response.status_code}")
			print(f"[DEBUG] Response body: {response.text!r}")
			print(f"[DEBUG] Response headers: {dict(response.headers)}")
			return

		def wait(retries):
			if ~{max_python_retries} - retries == 1:
				print("WAITING ONE MINUTE, THEN RETRYING...")
				time.sleep(60)
			else:
				print("WAITING TWO SECONDS, THEN RETRYING...")
				time.sleep(2)

		def delete_mr_project(token, mr_url, retries=-1):
			if retries < ~{max_python_retries}:
				try:
					response = requests.post("https://microreact.org/api/projects/bin/",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						timeout=120,
						params={"project": mr_url})
					if verbose:
						debug_print(response)
					if response.status_code == 200:
						print(f"Deleted {mr_url}")
						return
					print(f"Failed to delete MR project {mr_url} [code {response.status_code}]: {response.text}")
					retries =+ 1
					wait(retries)
					delete_mr_project(token, mr_url, retries)
				except Exception as e:
					print(f"Caught exception trying to delete MR project {mr_url}: {e}")
					retries =+ 1
					wait(retries)
					delete_mr_project(token, mr_url, retries)
			else:
				print(f"Failed to delete MR project {mr_url} after ~{max_python_retries} retries. Something's broken.")
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
		maxRetries: max_wdl_retries
	}
}
